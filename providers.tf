terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

###############################################################################
# Region / provider wiring (read before use)
#
# This module does NOT declare a `region` variable (region model) and does
# NOT hard-code a provider. The Verified Access instance, its trust providers,
# groups, endpoints, and logging configuration are all created with the single
# inherited `aws` provider, so the *caller* decides the Region by choosing which
# provider configuration to pass into the `aws` slot.
#
# Verified Access is a REGIONAL service with no us-east-1 coupling (unlike
# CloudFront/WAFv2-CLOUDFRONT/ACM-for-CloudFront) — the ACM certificate wired into
# `domain_certificate_arn` must be a regional cert in the SAME Region as this module.
#
# module "verified_access" {
# source = "git::https://github.com/microsoftexpert/terraform-aws-verified-access?ref=v1.0.0"
# # inherits the default `aws` provider (whatever Region it points at)
# instance_description = "core-ztna"
#...
# }
#
# Provider credentials, default_tags and assume_role all live in the caller's
# provider block — never in this module.
###############################################################################
