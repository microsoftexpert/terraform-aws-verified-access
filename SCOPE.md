# tf-mod-aws-verified-access — SCOPE

Composite module for AWS Verified Access — the ZTNA (Zero Trust Network Access)
service that replaces a traditional corporate VPN for private application access. It
owns the Verified Access instance, one or more trust providers (identity and/or
device), the instance-to-trust-provider attachment(s), one or more access groups
(each carrying a Cedar `policy_document`), one or more endpoints (the actual
per-application front doors, backed by an ALB or a network interface), and the
instance's access-logging configuration — so a single module call produces a
complete, logged, policy-gated Zero Trust front end for one or more internal
applications.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_verifiedaccess_instance.this`

## In-scope resources

The module manages the following (allow-list) — confirmed against `hashicorp/aws`
v6.54.0 via the terraform-registry MCP; no other Verified Access resources exist in
the provider today:

- `aws_verifiedaccess_instance` — keystone
- `aws_verifiedaccess_trust_provider` — identity (OIDC / IAM Identity Center /
  native-app OIDC) or device (Jamf / CrowdStrike / JumpCloud) trust source (`for_each`)
- `aws_verifiedaccess_instance_trust_provider_attachment` — links each trust
  provider to the instance (`for_each`, one per trust provider)
- `aws_verifiedaccess_group` — Cedar policy container that endpoints attach to (`for_each`)
- `aws_verifiedaccess_endpoint` — the per-application ZTNA front door (`for_each`)
- `aws_verifiedaccess_instance_logging_configuration` — instance-wide access-log
  destination(s) (singleton, toggle via `for_each` 0/1 pattern)

## Out-of-scope resources (consumed by reference)

Referenced by `id`/`arn`, never created here:

- ACM certificate — `domain_certificate_arn` (from `tf-mod-aws-acm`, regional —
  the endpoint is a regional resource, not a CloudFront/us-east-1 one)
- Application Load Balancer — `load_balancer_arn` (from `tf-mod-aws-lb`, for
  `endpoint_type = "load-balancer"`)
- ENI — `network_interface_id` (from `tf-mod-aws-network-interface`, for
  `endpoint_type = "network-interface"`)
- Security group(s) — `security_group_ids` (from `tf-mod-aws-security-group`)
- Subnet IDs — `load_balancer_options.subnet_ids` (from `tf-mod-aws-vpc`)
- KMS CMK — `sse_configuration.kms_key_arn` / `sse_specification.kms_key_arn`
  (from `tf-mod-aws-kms`, for group/endpoint/trust-provider encryption at rest)
- CloudWatch Log Group — `logging_configuration.cloudwatch_logs.log_group`
  (from `tf-mod-aws-cloudwatch-log-group`)
- Kinesis Data Firehose delivery stream / S3 bucket — external log destinations
  (from `tf-mod-aws-kinesis-firehose` / `tf-mod-aws-s3-bucket`)
- IAM Identity Center — the `iam-identity-center` user-trust-provider type consumes
  the account's existing IAM Identity Center instance; not created here
- Third-party IdP (Okta/Azure AD/etc.) and third-party device-trust vendor (Jamf/
  CrowdStrike/JumpCloud) tenants — configured out-of-band; only referenced by
  `client_id`/`client_secret`/`issuer`/`tenant_id`

## Consumes

| Input | Type | Source module |
|---|---|---|
| `endpoints[*].load_balancer_options.load_balancer_arn` | `string` (ALB ARN) | `tf-mod-aws-lb` |
| `endpoints[*].load_balancer_options.subnet_ids` | `list(string)` | `tf-mod-aws-vpc` |
| `endpoints[*].network_interface_options.network_interface_id` | `string` (ENI id) | `tf-mod-aws-network-interface` |
| `endpoints[*].domain_certificate_arn` | `string` (ACM cert ARN, regional) | `tf-mod-aws-acm` |
| `endpoints[*].security_group_ids` | `list(string)` | `tf-mod-aws-security-group` |
| `endpoints[*].sse_specification.kms_key_arn`, `groups[*].sse_configuration.kms_key_arn`, `trust_providers[*].sse_specification.kms_key_arn` | `string` (CMK ARN) | `tf-mod-aws-kms` |
| `logging_configuration.cloudwatch_logs.log_group` | `string` (log group name/ARN) | `tf-mod-aws-cloudwatch-log-group` |

> **Foundation-adjacent module** — Verified Access sits at the network-access edge; it
> depends on ACM, VPC/security groups, KMS, and (for load-balancer endpoints) `tf-mod-aws-lb`
> already being deployed, but nothing downstream depends on it structurally (it is a
> terminal/edge module in the dependency graph, alongside CloudFront/WAFv2).

## Required IAM permissions

Verified Access has **no dedicated IAM service prefix** — every action lives under
`ec2:` (a common EC2-family quirk shared with, e.g., Transit Gateway). Least-privilege
actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `ec2:CreateVerifiedAccessInstance`, `ec2:DeleteVerifiedAccessInstance`, `ec2:DescribeVerifiedAccessInstances`, `ec2:ModifyVerifiedAccessInstance` | Instance lifecycle |
| `ec2:CreateVerifiedAccessTrustProvider`, `ec2:DeleteVerifiedAccessTrustProvider`, `ec2:DescribeVerifiedAccessTrustProviders`, `ec2:ModifyVerifiedAccessTrustProvider` | Trust-provider lifecycle |
| `ec2:AttachVerifiedAccessTrustProvider`, `ec2:DetachVerifiedAccessTrustProvider` | Instance ↔ trust-provider attachment |
| `ec2:CreateVerifiedAccessGroup`, `ec2:DeleteVerifiedAccessGroup`, `ec2:DescribeVerifiedAccessGroups`, `ec2:ModifyVerifiedAccessGroupPolicy`, `ec2:ModifyVerifiedAccessGroup` | Group + Cedar policy lifecycle |
| `ec2:CreateVerifiedAccessEndpoint`, `ec2:DeleteVerifiedAccessEndpoint`, `ec2:DescribeVerifiedAccessEndpoints`, `ec2:ModifyVerifiedAccessEndpointPolicy`, `ec2:ModifyVerifiedAccessEndpoint` | Endpoint lifecycle + Cedar policy |
| `ec2:ModifyVerifiedAccessInstanceLoggingConfiguration`, `ec2:DescribeVerifiedAccessInstanceLoggingConfigurations` | Access-log wiring |
| `ec2:CreateTags`, `ec2:DeleteTags`, `ec2:DescribeTags` | Tagging (all VA resources are tagged EC2-family objects) |
| `kms:DescribeKey`, `kms:CreateGrant` | Only when a customer-managed key is supplied for `sse_configuration`/`sse_specification` |
| `elasticloadbalancing:DescribeLoadBalancers` | Resolving `load_balancer_arn` on `load-balancer` endpoints |
| `ec2:DescribeNetworkInterfaces` | Resolving `network_interface_id` on `network-interface` endpoints |
| `acm:DescribeCertificate` | Resolving `domain_certificate_arn` |

No `iam:PassRole` is required — Verified Access does not assume a service role on the
caller's behalf for these resources.

## AWS Prerequisites

- **No service-linked role** is required for Verified Access.
- **Identity trust provider must exist before it is useful.** For `user_trust_provider_type
  = "oidc"`, an OIDC-compliant IdP (Okta, Azure AD, Ping, etc.) must already expose
  `authorization_endpoint`/`token_endpoint`/`user_info_endpoint` and a registered
  `client_id`/`client_secret` **before** `terraform apply`. For `"iam-identity-center"`,
  IAM Identity Center must already be enabled for the AWS Organization/account.
- **Device trust provider must exist before it is useful.** Jamf, CrowdStrike, or
  JumpCloud must already have their AWS Verified Access integration configured
  (tenant enrolled, `tenant_id` issued) before `device_options.tenant_id` is wired in —
  this module does not configure the vendor side.
- **Cedar policy language.** `policy_document` on both groups and endpoints is written
  in Cedar (the same policy language behind Amazon Verified Permissions), not IAM JSON.
  A syntactically valid but semantically wrong Cedar policy still applies cleanly
  (`terraform apply` will not catch a logic error) — test policies in the Verified
  Access / Verified Permissions console policy validator or the `cedar` CLI before
  committing them to this module's `policy_document` inputs.
- **Region constraint:** none — Verified Access is a regional service; no us-east-1
  requirement (unlike CloudFront/WAFv2-CLOUDFRONT/ACM-for-CloudFront).
- **Quotas:** default 10 Verified Access instances per account/Region, 5 trust
  providers per instance, 10 groups per instance, 150 endpoints per instance (soft,
  raisable via Service Quotas) — call out before scaling to many applications per instance.
- **DNS delegation for `load-balancer`/`network-interface` endpoints.** The generated
  `endpoint_domain` (`<endpoint_domain_prefix>.<instance-subdomain>.vai.<region>....`)
  needs a CNAME from the caller's own `application_domain` — provisioned in
  `tf-mod-aws-route53-zone`, not here.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Verified Access instance id | `logging_configuration`, cross-module reference |
| `creation_time` / `last_updated_time` | Instance lifecycle timestamps | audit |
| `name_servers` | Instance-level name servers backing CIDR endpoints | DNS diagnostics |
| `trust_provider_ids` | Map of trust-provider key → id | attachment wiring, audit |
| `group_ids` | Map of group key → id | endpoint wiring |
| `group_arns` | Map of group key → ARN (`verifiedaccess_group_arn`) | `tf-mod-aws-kms` grant scoping, IAM policy conditions |
| `endpoint_ids` | Map of endpoint key → id | audit, DNS automation |
| `endpoint_domains` | Map of endpoint key → generated `endpoint_domain` | `tf-mod-aws-route53-zone` (CNAME target) |
| `endpoint_device_validation_domains` | Map of endpoint key → device-validation domain (null unless a device trust provider is attached) | device-trust vendor DNS validation |
| `tags_all` | All tags incl. provider `default_tags`, from the instance | governance/audit |

> **No module-level `arn` output** — see Provider gotchas below. `group_arns` is the
> only true ARN this module emits (`aws_verifiedaccess_group` is the sole VA resource
> with an ARN attribute).

## Provider gotchas

- **`aws_verifiedaccess_instance`, `aws_verifiedaccess_trust_provider`, and
  `aws_verifiedaccess_endpoint` expose NO `arn` attribute at all** — confirmed against
  the live v6.54.0 schema (only `id`, and for the endpoint also `endpoint_domain` /
  `device_validation_domain`). Only `aws_verifiedaccess_group` has an ARN, named
  `verifiedaccess_group_arn` (not the generic `arn`). This module therefore departs
  from the usual "emit `id` + `arn`" convention at the instance/trust-provider/endpoint
  level — documented rather than fabricated, per this module suite's "where the resource
  exposes them" carve-out.
- **An instance must have a trust provider ATTACHED before groups/endpoints are
  meaningful.** A group/endpoint can technically be created against an instance with
  zero attached trust providers, but every request will fail Cedar evaluation (no
  identity/device context exists). `main.tf` models this with an explicit
  `depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.this]` on both
  `aws_verifiedaccess_group.this` and `aws_verifiedaccess_endpoint.this` so Terraform
  always attaches trust providers first, even though no argument reference forces
  that ordering.
- **`trust_provider_type`, `device_trust_provider_type`, and `user_trust_provider_type`
  are effectively FORCE-NEW-adjacent** — the provider allows changing some OIDC
  fields in place, but switching the trust-provider *type* replaces the resource and
  breaks the instance attachment; re-attach is required.
- **`policy_document` is Cedar, not IAM JSON — and it is easy to get subtly wrong.**
  A policy with a typo in a principal/action/resource clause can silently evaluate to
  "deny everything" or, worse, "permit more than intended." Validate every policy in
  the AWS console's Verified Access policy validator (or the Cedar CLI/playground)
  before applying. This module does not (and cannot) lint Cedar syntax.
  it's important that `policy_document` scope clauses (`principal`, `action`,
  `resource`) are always left undefined per AWS's Cedar dialect for Verified Access —
  only `when`/`unless` condition clauses should reference `context`.
- **Fail-closed by default.** AWS's own Verified Access behavior is deny-by-default —
  a group or endpoint with `policy_document = null` denies all access. This module
  relies on that native behavior instead of re-implementing a synthetic deny policy;
  document this in any onboarding runbook so callers don't mistake "no policy" for
  "open access."
- **`aws_verifiedaccess_instance_logging_configuration` is a singleton keyed only by
  `verifiedaccess_instance_id` (FORCE-NEW on that id).** Destroying this resource
  resets the instance's logging to AWS defaults (no logging) rather than deleting
  anything in EC2's sense — documented so an operator isn't surprised the "delete"
  is really "revert to unlogged."
  destination log group/bucket/stream is NOT created or IAM-authorized by this
  module — the S3 bucket policy / CloudWatch Logs resource policy / Firehose IAM role
  granting the Verified Access log-delivery principal write access must already exist
  (same eventual-consistency gotcha as ALB access logging in `tf-mod-aws-lb`).
- **`endpoint_domain_prefix` and `attachment_type` are effectively FORCE-NEW.** The
  module hard-codes `attachment_type = "vpc"` (the only value the provider currently
  accepts) rather than exposing it as a variable, to keep the caller surface honest
  about what is actually configurable today.
- **Region model:** every resource accepts the v6 `region` argument for multi-region
  support, but this module relies on provider inheritance (no `region` variable) per
  the Casey's region model — Verified Access is not a global/us-east-1 service.
- **Out-of-scope endpoint types.** The live schema also exposes `cidr_options` and
  `rds_options` endpoint variants (CIDR-block and RDS-backed Verified Access
  endpoints). This module deliberately scopes to `load-balancer` and
  `network-interface` only — the two application-facing patterns Casey's uses today.
  Extending to `cidr`/`rds` is a documented follow-up, not an oversight.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Access logging | **`logging_configuration.enabled = true`** — at least one of `cloudwatch_logs`/`kinesis_data_firehose`/`s3` must be supplied (validation enforces this, mirroring `tf-mod-aws-lb`'s `access_logs` pattern) | `logging_configuration.enabled = false` (discouraged — removes the only audit trail of ZTNA access decisions) |
| Trust-context in logs | `include_trust_context = true` — device/identity claims are included in every log line for investigative auditability | `include_trust_context = false` |
| Group/endpoint policy | **no baked-in default policy** — AWS's native fail-closed behavior (`policy_document = null` denies all) is relied on rather than re-implemented; callers must supply an explicit Cedar `permit` policy to grant any access | n/a — there is no "open" default to opt out of |
| Encryption at rest (group / endpoint / trust-provider Cedar policies & OIDC secrets) | AWS-owned key by default (`sse_configuration`/`sse_specification` omitted); CMK wiring is a first-class, documented option | supply `sse_configuration.kms_key_arn` / `sse_specification.kms_key_arn` with `customer_managed_key_enabled = true` |
| OIDC `client_secret` handling | `oidc_options.client_secret` / `native_application_oidc_options.client_secret` are marked `sensitive = true` **in the aws provider's own resource schema**, so Terraform automatically redacts those two values from plan/apply console output regardless of module wiring (the `trust_providers` variable itself is intentionally left non-sensitive because a sensitive value cannot be used as a `for_each` key set) | none — this redaction is non-negotiable for a GLBA/NPI-adjacent identity secret; state still holds the plaintext value, so protect Terraform state with encryption-at-rest and least-privilege access |

## Design decisions

- One composite owns the instance, its trust provider(s), the instance-attachment
  join resource, group(s), endpoint(s), and the logging configuration so a caller
  gets one complete, logged, policy-gated Zero Trust boundary from a single module
  call — mirroring `tf-mod-aws-lb`'s "one call, complete front end" philosophy.
- Trust providers, groups, and endpoints are each `for_each` over `map(object(...))`
  keyed by a stable caller string — no `count` — so adding/removing one trust
  provider or application never re-indexes the others.
- `endpoints[*].verified_access_group_key` is an internal wiring key (not an AWS
  argument) that lets the module resolve `aws_verifiedaccess_group.this[key].id`
  without requiring the caller to pre-compute ARNs/ids by hand — the same pattern
  `tf-mod-aws-lb` uses for `target_group_key` in `listeners`/`listener_rules`.
- The attachment join resource (`aws_verifiedaccess_instance_trust_provider_attachment`)
  is rendered 1:1 from `var.trust_providers` (same keys) rather than as its own
  variable, because Casey's usage pattern always attaches every configured trust
  provider to the one instance the module manages — a separate attachment map would
  only add caller-facing complexity with no real flexibility gained.
- ACM certificates are regional and referenced by `arn` from `tf-mod-aws-acm` — there
  is no us-east-1 coupling for Verified Access (unlike CloudFront/WAFv2).
