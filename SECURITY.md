# Security policy

Please report suspected secrets or infrastructure vulnerabilities privately to the repository owner. Do not publish credentials or state files in issues or PRs.

Supported configuration: the latest main branch. Changes to IAM trust, state buckets, NACLs, KMS and logging require review. Run `terraform plan` before apply. Do not disable failed security checks without a narrowly scoped documented exception.

Report evidence with redacted identifiers and timestamps. Never include live AccessKeyId/SecretAccessKey pairs, Terraform state, plan files or signed URLs.
