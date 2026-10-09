# Security model and residual risks

## Purpose
A defensive IaC reference that demonstrates least privilege and reproducible security controls for a single private EC2 workload. **Not a production certificate, HA design or substitute for an AWS account security review.**

## Threat boundaries
1. **GitHub and local workstation to AWS**: only verified, narrowly scoped AWS credentials should deploy. CI is manual-only and plan-only; deployment OIDC trust and GitHub protected environments must be configured in AWS and GitHub respectively.
2. **Terraform state**: state may contain passwords, user data or metadata even when outputs are marked sensitive. Private SSE-KMS S3, versioning, locking, TLS and restricted deployment IAM are required. Never upload plans/state to GitHub artifacts.
3. **Network**: the workload has no public IP or inbound service port. PrivateLink endpoints admit only the instance SG. The NAT feature is opt-in and **permits outbound HTTPS to all destinations**; use a proxy/egress firewall plus domain allowlists if production workloads require strict outbound controls. The default subnet NACL remains AWS's permissive default; SGs are the primary boundary.
4. **Runtime**: EC2 requires IMDSv2, disk encryption and SSM instance role. AWS-managed SSM policy is broader than a workload-specific permission boundary; application permissions must be a separate role or specifically scoped policies. Patch management must be solved via immutable AMIs or controlled outbound access.
5. **Audit evidence**: CloudTrail is multi-region and writes to a protected SSE-KMS/versioned bucket. VPC Flow Logs send to CloudWatch. EventBridge can alert on tampering. Delivery, subscription confirmation and KMS authorization require real AWS smoke tests.
6. **Bastion**: optional SSH host is off by default; only use with an approved /32 and key rotation. The bastion is not redundant HA infrastructure. Remove it after troubleshooting.

## Deliberate exclusions
- No direct Internet-exposed web service, ALB, DNS, WAF or application credentials.
- No automatic Terraform apply, global administrator role, or embedded access keys.
- No guaranteed two-AZ availability; the implementation intentionally uses one AZ.
- No automated AWS Backup restore verification, patch window, vulnerability agent deployment, CIS full compliance evidence or SSM session-content recording.
- No claim that encrypted SNS/CloudTrail delivery is operational before live verification.

## Release gates
- Repository formatting, provider validation, mocked Terraform tests and high/critical IaC scans pass locally.
- IAM trust, CloudTrail+S3 encryption, session access and KMS policies validated by AWS deployment with recorded test evidence.
- Terraform backend bucket/CMK isolated from workload account when appropriate and policies reviewed.
- Update repository README and evidence with current test date; document accepted exceptions and costs.
