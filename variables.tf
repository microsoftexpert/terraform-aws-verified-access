###############################################################################
# Identity (instance-level)
###############################################################################

variable "instance_description" {
 description = <<EOT
A description for the AWS Verified Access instance (the keystone resource this
module builds around). Optional — leave null for an undescribed instance.
EOT
 type = string
 default = null
}

variable "fips_enabled" {
 description = <<EOT
Whether Federal Information Processing Standards (FIPS) endpoints are enabled on
the Verified Access instance. FORCE-NEW — changing this replaces the instance.
Defaults to false (the AWS default); set true only for workloads under a FIPS
140-2/3 compliance requirement.
EOT
 type = bool
 default = false
}

variable "cidr_endpoints_custom_subdomain" {
 description = <<EOT
Custom subdomain used to generate DNS names for this instance's CIDR-type
endpoints. Null (default) lets AWS generate the standard subdomain. Only relevant
if a future `cidr_options` endpoint variant is added; harmless to leave null for
load-balancer/network-interface endpoints.
EOT
 type = string
 default = null
}

###############################################################################
# Trust providers (child collection — for_each over map(object))
#
# SECRET-BEARING: oidc_options.client_secret and native_application_oidc_options
#.client_secret are marked `sensitive = true` in the aws provider's own resource
# schema, so Terraform automatically redacts those two values from plan/apply
# console output and `terraform show` — this variable is intentionally NOT marked
# sensitive as a whole (a sensitive value cannot be used as a for_each key set, and
# the per-attribute provider-schema redaction already covers the actual secret).
# The values are still stored in plaintext in Terraform state; protect state with
# encryption-at-rest and least-privilege state access, same as any other secret.
###############################################################################

variable "trust_providers" {
 description = <<EOT
Map of Verified Access trust providers keyed by a stable name, each rendered as one
aws_verifiedaccess_trust_provider AND automatically attached to this module's
instance via aws_verifiedaccess_instance_trust_provider_attachment (one attachment
per key — see Design decisions in SCOPE.md). At least one trust provider should be
supplied before any group/endpoint policy can evaluate meaningfully; AWS Verified
Access is fail-closed without one.

 - policy_reference_name: identifier used to reference this provider's context
 in Cedar policy_document expressions (e.g. context.<name>.*).
 - trust_provider_type: "user" or "device". FORCE-NEW-adjacent — switching type
 replaces the trust provider.
 - description: optional human-readable description.
 - user_trust_provider_type: required when trust_provider_type = "user". One of
 "iam-identity-center" or "oidc".
 - device_trust_provider_type: required when trust_provider_type = "device". One of
 "jamf", "jumpcloud", or "crowdstrike".
 - device_options: { tenant_id } — the vendor tenant id issued when the device-trust
 vendor's AWS Verified Access integration was configured
 out-of-band (see SCOPE.md AWS Prerequisites).
 - oidc_options: OIDC endpoint details for user_trust_provider_type = "oidc".
 { authorization_endpoint, client_id, client_secret (REQUIRED
 within this block, sensitive), issuer, scope, token_endpoint,
 user_info_endpoint } — all HTTPS URLs except client_id/secret/scope.
 - native_application_oidc_options: same shape as oidc_options plus
 public_signing_key_endpoint, for a native (mobile/desktop) OIDC app
 instead of a browser-redirect OIDC flow.
 - sse_specification: { customer_managed_key_enabled, kms_key_arn } — encrypts this
 trust provider's OIDC secrets/config at rest with a CMK. Wire
 kms_key_arn from tf-mod-aws-kms. Null uses the AWS-owned key.
 - tags: extra tags merged over module tags for this trust provider.
EOT
 type = map(object({
 policy_reference_name = string
 trust_provider_type = string
 description = optional(string)
 user_trust_provider_type = optional(string)
 device_trust_provider_type = optional(string)
 device_options = optional(object({
 tenant_id = optional(string)
 }))
 oidc_options = optional(object({
 authorization_endpoint = optional(string)
 client_id = optional(string)
 client_secret = optional(string)
 issuer = optional(string)
 scope = optional(string)
 token_endpoint = optional(string)
 user_info_endpoint = optional(string)
 }))
 native_application_oidc_options = optional(object({
 authorization_endpoint = optional(string)
 client_id = optional(string)
 client_secret = optional(string)
 issuer = optional(string)
 public_signing_key_endpoint = optional(string)
 scope = optional(string)
 token_endpoint = optional(string)
 user_info_endpoint = optional(string)
 }))
 sse_specification = optional(object({
 customer_managed_key_enabled = optional(bool, false)
 kms_key_arn = optional(string)
 }))
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.trust_providers: contains(["user", "device"], v.trust_provider_type)])
 error_message = "Each trust_providers[*].trust_provider_type must be one of: user, device."
 }

 validation {
 condition = alltrue([
 for k, v in var.trust_providers:
 v.user_trust_provider_type == null || contains(["iam-identity-center", "oidc"], v.user_trust_provider_type)
 ])
 error_message = "Each trust_providers[*].user_trust_provider_type must be one of: iam-identity-center, oidc (or null)."
 }

 validation {
 condition = alltrue([
 for k, v in var.trust_providers:
 v.device_trust_provider_type == null || contains(["jamf", "jumpcloud", "crowdstrike"], v.device_trust_provider_type)
 ])
 error_message = "Each trust_providers[*].device_trust_provider_type must be one of: jamf, jumpcloud, crowdstrike (or null)."
 }
}

###############################################################################
# Groups (child collection — for_each over map(object))
###############################################################################

variable "groups" {
 description = <<EOT
Map of Verified Access groups keyed by a stable name, each rendered as one
aws_verifiedaccess_group attached to this module's instance. Endpoints reference a
group by key via endpoints[*].verified_access_group_key.

SECURE DEFAULT: policy_document defaults to null, which AWS evaluates as
deny-by-default (fail-closed) — there is no synthetic "allow all" default to opt
out of. Supply an explicit Cedar permit policy to grant access.

 - description: optional human-readable description.
 - policy_document: Cedar policy text (NOT IAM JSON). Validate in the AWS console
 Verified Access policy validator before applying — Terraform
 cannot lint Cedar syntax or semantics.
 - sse_configuration: { customer_managed_key_enabled, kms_key_arn } — encrypts this
 group's Cedar policy at rest with a CMK. Wire kms_key_arn
 from tf-mod-aws-kms. Null uses the AWS-owned key.
 - tags: extra tags merged over module tags for this group.
EOT
 type = map(object({
 description = optional(string)
 policy_document = optional(string)
 sse_configuration = optional(object({
 customer_managed_key_enabled = optional(bool, false)
 kms_key_arn = optional(string)
 }))
 tags = optional(map(string), {})
 }))
 default = {}
}

###############################################################################
# Endpoints (child collection — for_each over map(object))
#
# Scoped to endpoint_type "load-balancer" and "network-interface" only (the two
# application-facing patterns uses today). See SCOPE.md for the documented
# out-of-scope cidr/rds endpoint variants.
###############################################################################

variable "endpoints" {
 description = <<EOT
Map of Verified Access endpoints keyed by a stable name, each rendered as one
aws_verifiedaccess_endpoint — the actual per-application ZTNA front door.
attachment_type is hard-coded to "vpc" (the only value the provider currently
accepts) so it is not exposed here.

 - endpoint_type: "load-balancer" or "network-interface". FORCE-NEW.
 Determines which of load_balancer_options /
 network_interface_options is required (enforced by
 validation below).
 - application_domain: DNS name end users use to reach the application
 (e.g. "app.internal.example.com"). Required for both
 supported endpoint_type values.
 - domain_certificate_arn: ACM certificate ARN (regional — same Region as this
 module) whose CN matches application_domain. Wire
 from tf-mod-aws-acm. Required for both supported
 endpoint_type values.
 - endpoint_domain_prefix: custom subdomain prepended to the AWS-generated
 endpoint_domain. Required by the provider — FORCE-NEW.
 - description: optional human-readable description.
 - security_group_ids: security groups applied to the endpoint's ENIs. Wire
 from tf-mod-aws-security-group.
 - load_balancer_options: required when endpoint_type = "load-balancer".
 { load_balancer_arn (FORCE-NEW, wire from tf-mod-aws-lb),
 port, protocol ("http"|"https", default "https"),
 subnet_ids (wire from tf-mod-aws-vpc),
 port_range = { from_port, to_port } for a multi-port
 range instead of a single port }.
 - network_interface_options: required when endpoint_type = "network-interface".
 { network_interface_id (FORCE-NEW, wire from
 tf-mod-aws-network-interface), port,
 protocol ("http"|"https", default "https"),
 port_range = { from_port, to_port } }.
 - policy_document: endpoint-level Cedar policy, evaluated in addition to
 the attached group's policy. Null (default) adds no
 extra restriction beyond the group policy.
 - sse_specification: { customer_managed_key_enabled, kms_key_arn } —
 encrypts this endpoint's Cedar policy at rest with a
 CMK. Wire kms_key_arn from tf-mod-aws-kms.
 - verified_access_group_key: key into var.groups — internal wiring, not an AWS
 argument — that this endpoint attaches to.
 - tags: extra tags merged over module tags for this endpoint.
EOT
 type = map(object({
 endpoint_type = string
 application_domain = string
 domain_certificate_arn = string
 endpoint_domain_prefix = string
 description = optional(string)
 security_group_ids = optional(list(string), [])
 load_balancer_options = optional(object({
 load_balancer_arn = string
 port = optional(number)
 protocol = optional(string, "https")
 subnet_ids = optional(list(string), [])
 port_range = optional(object({
 from_port = number
 to_port = number
 }))
 }))
 network_interface_options = optional(object({
 network_interface_id = string
 port = optional(number)
 protocol = optional(string, "https")
 port_range = optional(object({
 from_port = number
 to_port = number
 }))
 }))
 policy_document = optional(string)
 sse_specification = optional(object({
 customer_managed_key_enabled = optional(bool, false)
 kms_key_arn = optional(string)
 }))
 verified_access_group_key = string
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.endpoints: contains(["load-balancer", "network-interface"], v.endpoint_type)])
 error_message = "Each endpoints[*].endpoint_type must be one of: load-balancer, network-interface (cidr/rds are out of scope — see SCOPE.md)."
 }

 validation {
 condition = alltrue([
 for k, v in var.endpoints:
 v.endpoint_type != "load-balancer" || v.load_balancer_options != null
 ])
 error_message = "Each endpoints[*] with endpoint_type = \"load-balancer\" must set load_balancer_options."
 }

 validation {
 condition = alltrue([
 for k, v in var.endpoints:
 v.endpoint_type != "network-interface" || v.network_interface_options != null
 ])
 error_message = "Each endpoints[*] with endpoint_type = \"network-interface\" must set network_interface_options."
 }

 validation {
 condition = alltrue([
 for k, v in var.endpoints: contains(["http", "https"], coalesce(try(v.load_balancer_options.protocol, null), try(v.network_interface_options.protocol, null), "https"))
 ])
 error_message = "Each endpoints[*].{load_balancer_options,network_interface_options}.protocol must be one of: http, https."
 }
}

###############################################################################
# Instance access logging (secure default: logging ON)
###############################################################################

variable "logging_configuration" {
 description = <<EOT
Access-logging configuration for this module's Verified Access instance, rendered as
one aws_verifiedaccess_instance_logging_configuration. SECURE DEFAULT: enabled =
true, so at least one of cloudwatch_logs, kinesis_data_firehose, or s3 MUST be
supplied — the empty default ({}) resolves to enabled=true with no destination and
fails validation, forcing an explicit choice: wire a destination or deliberately
opt out with enabled=false.

 - enabled: whether instance logging is configured at all (default
 true). Setting false (or destroying this resource) reverts
 the instance to AWS's default of no logging.
 - include_trust_context: whether device/identity trust-provider claims are
 included in every log line (default true — audit
 baseline).
 - log_version: logging schema version (e.g. "ocsf-1.0.0-rc.2"). Null
 uses the AWS default version.
 - cloudwatch_logs: { enabled (default true when block is set), log_group } — wire
 log_group from tf-mod-aws-cloudwatch-log-group.
 - kinesis_data_firehose: { enabled (default true when block is set), delivery_stream }
 — wire delivery_stream from tf-mod-aws-kinesis-firehose.
 - s3: { enabled (default true when block is set), bucket_name, bucket_owner, prefix }
 — wire bucket_name from tf-mod-aws-s3-bucket (log-archive). The bucket
 policy must already grant the Verified Access log-delivery principal
 write access, or the apply fails.

 logging_configuration = { cloudwatch_logs = { log_group = module.log_group.name } }
 logging_configuration = { enabled = false } # documented opt-out
EOT
 type = object({
 enabled = optional(bool, true)
 include_trust_context = optional(bool, true)
 log_version = optional(string)
 cloudwatch_logs = optional(object({
 enabled = optional(bool, true)
 log_group = optional(string)
 }))
 kinesis_data_firehose = optional(object({
 enabled = optional(bool, true)
 delivery_stream = optional(string)
 }))
 s3 = optional(object({
 enabled = optional(bool, true)
 bucket_name = optional(string)
 bucket_owner = optional(string)
 prefix = optional(string)
 }))
 })
 default = {}

 validation {
 condition = (var.logging_configuration.enabled == false ||
 var.logging_configuration.cloudwatch_logs != null ||
 var.logging_configuration.kinesis_data_firehose != null ||
 var.logging_configuration.s3 != null)
 error_message = "At least one of logging_configuration.{cloudwatch_logs,kinesis_data_firehose,s3} is required when logging_configuration.enabled is true. Supply a destination or set logging_configuration.enabled = false (documented opt-out)."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to all taggable resources created by this module (the
Verified Access instance, trust providers, groups, and endpoints). These merge with
provider-level default_tags; resource tags win on key conflict. Per-item tags on
trust providers, groups, and endpoints merge over this map. The computed tags_all
output reflects the merged set (from the instance). Instance-trust-provider
attachments and the instance logging configuration are not taggable.
EOT
 type = map(string)
 default = {}
}

variable "timeouts" {
 description = <<EOT
Optional Terraform operation timeouts, applied uniformly to every
aws_verifiedaccess_trust_provider and aws_verifiedaccess_endpoint this module
creates (both resources declare the same create/update/delete timeout shape in the
provider). aws_verifiedaccess_instance does not expose a configurable timeouts
block in the current schema, so this does not apply to the instance itself.

 - create: how long to wait for creation (provider default 60m).
 - update: how long to wait for updates (provider default 180m).
 - delete: how long to wait for deletion (provider default 90m).
EOT
 type = object({
 create = optional(string)
 update = optional(string)
 delete = optional(string)
 })
 default = {}
}
