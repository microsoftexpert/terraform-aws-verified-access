###############################################################################
# Primary output (id only — see Architecture Notes / SCOPE.md Provider gotchas)
#
# aws_verifiedaccess_instance exposes NO arn attribute in the current provider
# schema (confirmed against hashicorp/aws v6.54.0) — only aws_verifiedaccess_group
# has a true ARN (verifiedaccess_group_arn, surfaced below as group_arns). This
# module therefore departs from the usual id+arn pair at the instance level rather
# than fabricate an arn that does not exist.
###############################################################################

output "id" {
 description = "The ID of the Verified Access instance (e.g. vai-xxxxxxxxxxxxxxxxx)."
 value = aws_verifiedaccess_instance.this.id
}

output "creation_time" {
 description = "Timestamp when the Verified Access instance was created."
 value = aws_verifiedaccess_instance.this.creation_time
}

output "last_updated_time" {
 description = "Timestamp when the Verified Access instance was last updated."
 value = aws_verifiedaccess_instance.this.last_updated_time
}

output "name_servers" {
 description = "Name servers backing this instance's CIDR-type endpoints (informational; this module scopes to load-balancer/network-interface endpoints today)."
 value = aws_verifiedaccess_instance.this.name_servers
}

###############################################################################
# Trust providers
###############################################################################

output "trust_provider_ids" {
 description = "Map of trust-provider key => id. No arn attribute exists on this resource in the current provider schema."
 value = { for k, tp in aws_verifiedaccess_trust_provider.this: k => tp.id }
}

###############################################################################
# Groups
#
# The only true ARN this module emits — aws_verifiedaccess_group is the sole
# Verified Access resource exposing one, named verifiedaccess_group_arn (not the
# generic arn).
###############################################################################

output "group_ids" {
 description = "Map of group key => id (verifiedaccess_group_id)."
 value = { for k, g in aws_verifiedaccess_group.this: k => g.id }
}

output "group_arns" {
 description = <<EOT
Map of group key => ARN (verifiedaccess_group_arn) — the cross-resource reference
type for this module. Consumed by terraform-aws-kms grant scoping and any IAM policy
condition that needs to name a specific Verified Access group.
EOT
 value = { for k, g in aws_verifiedaccess_group.this: k => g.verifiedaccess_group_arn }
}

output "group_owners" {
 description = "Map of group key => AWS account id owning the group."
 value = { for k, g in aws_verifiedaccess_group.this: k => g.owner }
}

###############################################################################
# Endpoints
###############################################################################

output "endpoint_ids" {
 description = "Map of endpoint key => id. No arn attribute exists on this resource in the current provider schema."
 value = { for k, e in aws_verifiedaccess_endpoint.this: k => e.id }
}

output "endpoint_domains" {
 description = "Map of endpoint key => generated endpoint_domain. Wire into terraform-aws-route53-zone as the CNAME target for each application_domain."
 value = { for k, e in aws_verifiedaccess_endpoint.this: k => e.endpoint_domain }
}

output "endpoint_device_validation_domains" {
 description = "Map of endpoint key => device_validation_domain. Null unless a device trust provider is attached to this instance; used for device-trust vendor DNS validation."
 value = { for k, e in aws_verifiedaccess_endpoint.this: k => try(e.device_validation_domain, null) }
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the Verified Access instance, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_verifiedaccess_instance.this.tags_all
}
