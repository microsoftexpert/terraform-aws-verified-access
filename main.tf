###############################################################################
# Verified Access instance (keystone)
#
# description and cidr_endpoints_custom_subdomain are mutable in place;
# fips_enabled is FORCE-NEW. The instance itself has no configurable timeouts
# block in the current provider schema (see variables.tf var.timeouts).
###############################################################################

resource "aws_verifiedaccess_instance" "this" {
 description = var.instance_description
 fips_enabled = var.fips_enabled
 cidr_endpoints_custom_subdomain = var.cidr_endpoints_custom_subdomain

 tags = var.tags
}

###############################################################################
# Trust providers
#
# trust_provider_type/user_trust_provider_type/device_trust_provider_type are
# FORCE-NEW-adjacent (switching type replaces the resource). Exactly one of
# device_options/oidc_options/native_application_oidc_options is rendered per key,
# matching whichever the caller populated.
###############################################################################

resource "aws_verifiedaccess_trust_provider" "this" {
 for_each = var.trust_providers

 policy_reference_name = each.value.policy_reference_name
 trust_provider_type = each.value.trust_provider_type
 description = try(each.value.description, null)
 user_trust_provider_type = try(each.value.user_trust_provider_type, null)
 device_trust_provider_type = try(each.value.device_trust_provider_type, null)

 dynamic "device_options" {
 for_each = try(each.value.device_options, null) != null ? [each.value.device_options]: []
 content {
 tenant_id = try(device_options.value.tenant_id, null)
 }
 }

 dynamic "oidc_options" {
 for_each = try(each.value.oidc_options, null) != null ? [each.value.oidc_options]: []
 content {
 authorization_endpoint = try(oidc_options.value.authorization_endpoint, null)
 client_id = try(oidc_options.value.client_id, null)
 client_secret = try(oidc_options.value.client_secret, null)
 issuer = try(oidc_options.value.issuer, null)
 scope = try(oidc_options.value.scope, null)
 token_endpoint = try(oidc_options.value.token_endpoint, null)
 user_info_endpoint = try(oidc_options.value.user_info_endpoint, null)
 }
 }

 dynamic "native_application_oidc_options" {
 for_each = try(each.value.native_application_oidc_options, null) != null ? [each.value.native_application_oidc_options]: []
 content {
 authorization_endpoint = try(native_application_oidc_options.value.authorization_endpoint, null)
 client_id = try(native_application_oidc_options.value.client_id, null)
 client_secret = try(native_application_oidc_options.value.client_secret, null)
 issuer = try(native_application_oidc_options.value.issuer, null)
 public_signing_key_endpoint = try(native_application_oidc_options.value.public_signing_key_endpoint, null)
 scope = try(native_application_oidc_options.value.scope, null)
 token_endpoint = try(native_application_oidc_options.value.token_endpoint, null)
 user_info_endpoint = try(native_application_oidc_options.value.user_info_endpoint, null)
 }
 }

 dynamic "sse_specification" {
 for_each = try(each.value.sse_specification, null) != null ? [each.value.sse_specification]: []
 content {
 customer_managed_key_enabled = try(sse_specification.value.customer_managed_key_enabled, false)
 kms_key_arn = try(sse_specification.value.kms_key_arn, null)
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))

 dynamic "timeouts" {
 for_each = (var.timeouts.create != null || var.timeouts.update != null || var.timeouts.delete != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Instance <-> trust provider attachments
#
# One attachment per configured trust provider, keyed identically to
# var.trust_providers (see Design decisions in SCOPE.md). Groups and endpoints
# depend_on this whole resource so Terraform always attaches trust providers
# before anything that relies on them being present for Cedar evaluation.
###############################################################################

resource "aws_verifiedaccess_instance_trust_provider_attachment" "this" {
 for_each = var.trust_providers

 verifiedaccess_instance_id = aws_verifiedaccess_instance.this.id
 verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.this[each.key].id
}

###############################################################################
# Groups
#
# policy_document defaults to null (AWS fail-closed behavior — see SCOPE.md).
###############################################################################

resource "aws_verifiedaccess_group" "this" {
 for_each = var.groups

 verifiedaccess_instance_id = aws_verifiedaccess_instance.this.id
 description = try(each.value.description, null)
 policy_document = try(each.value.policy_document, null)

 dynamic "sse_configuration" {
 for_each = try(each.value.sse_configuration, null) != null ? [each.value.sse_configuration]: []
 content {
 customer_managed_key_enabled = try(sse_configuration.value.customer_managed_key_enabled, false)
 kms_key_arn = try(sse_configuration.value.kms_key_arn, null)
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))

 depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.this]
}

###############################################################################
# Endpoints
#
# attachment_type is hard-coded to "vpc" (the only provider-accepted value).
# Exactly one of load_balancer_options/network_interface_options is rendered per
# key, gated on endpoint_type (enforced by variable validation).
###############################################################################

resource "aws_verifiedaccess_endpoint" "this" {
 for_each = var.endpoints

 attachment_type = "vpc"
 endpoint_type = each.value.endpoint_type
 application_domain = each.value.application_domain
 domain_certificate_arn = each.value.domain_certificate_arn
 endpoint_domain_prefix = each.value.endpoint_domain_prefix
 description = try(each.value.description, null)
 security_group_ids = try(each.value.security_group_ids, [])
 policy_document = try(each.value.policy_document, null)
 verified_access_group_id = aws_verifiedaccess_group.this[each.value.verified_access_group_key].id

 dynamic "load_balancer_options" {
 for_each = each.value.endpoint_type == "load-balancer" && each.value.load_balancer_options != null ? [each.value.load_balancer_options]: []
 content {
 load_balancer_arn = load_balancer_options.value.load_balancer_arn
 port = try(load_balancer_options.value.port, null)
 protocol = try(load_balancer_options.value.protocol, "https")
 subnet_ids = try(load_balancer_options.value.subnet_ids, [])

 dynamic "port_range" {
 for_each = try(load_balancer_options.value.port_range, null) != null ? [load_balancer_options.value.port_range]: []
 content {
 from_port = port_range.value.from_port
 to_port = port_range.value.to_port
 }
 }
 }
 }

 dynamic "network_interface_options" {
 for_each = each.value.endpoint_type == "network-interface" && each.value.network_interface_options != null ? [each.value.network_interface_options]: []
 content {
 network_interface_id = network_interface_options.value.network_interface_id
 port = try(network_interface_options.value.port, null)
 protocol = try(network_interface_options.value.protocol, "https")

 dynamic "port_range" {
 for_each = try(network_interface_options.value.port_range, null) != null ? [network_interface_options.value.port_range]: []
 content {
 from_port = port_range.value.from_port
 to_port = port_range.value.to_port
 }
 }
 }
 }

 dynamic "sse_specification" {
 for_each = try(each.value.sse_specification, null) != null ? [each.value.sse_specification]: []
 content {
 customer_managed_key_enabled = try(sse_specification.value.customer_managed_key_enabled, false)
 kms_key_arn = try(sse_specification.value.kms_key_arn, null)
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))

 dynamic "timeouts" {
 for_each = (var.timeouts.create != null || var.timeouts.update != null || var.timeouts.delete != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }

 depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.this]
}

###############################################################################
# Instance access-logging configuration (secure default: rendered unless the
# caller opts out via logging_configuration.enabled = false)
###############################################################################

resource "aws_verifiedaccess_instance_logging_configuration" "this" {
 for_each = var.logging_configuration.enabled ? { enabled = true }: {}

 verifiedaccess_instance_id = aws_verifiedaccess_instance.this.id

 access_logs {
 include_trust_context = var.logging_configuration.include_trust_context
 log_version = try(var.logging_configuration.log_version, null)

 dynamic "cloudwatch_logs" {
 for_each = var.logging_configuration.cloudwatch_logs != null ? [var.logging_configuration.cloudwatch_logs]: []
 content {
 enabled = try(cloudwatch_logs.value.enabled, true)
 log_group = try(cloudwatch_logs.value.log_group, null)
 }
 }

 dynamic "kinesis_data_firehose" {
 for_each = var.logging_configuration.kinesis_data_firehose != null ? [var.logging_configuration.kinesis_data_firehose]: []
 content {
 enabled = try(kinesis_data_firehose.value.enabled, true)
 delivery_stream = try(kinesis_data_firehose.value.delivery_stream, null)
 }
 }

 dynamic "s3" {
 for_each = var.logging_configuration.s3 != null ? [var.logging_configuration.s3]: []
 content {
 enabled = try(s3.value.enabled, true)
 bucket_name = try(s3.value.bucket_name, null)
 bucket_owner = try(s3.value.bucket_owner, null)
 prefix = try(s3.value.prefix, null)
 }
 }
 }
}
