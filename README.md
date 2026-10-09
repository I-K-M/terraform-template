# Secure AWS Terraform Platform

Terraform + Ansible reference deployment for a **private single-AZ EC2 workload** with IAM roles, IMDSv2, encrypted EBS, private SSM connectivity, optional NAT/bastion, CloudTrail and VPC Flow Logs.

This is a demonstration/reference deployment, **not certified production infrastructure**. No AWS resources are deployed by CI. Default deployment has no SSH ingress, no public workload IP and no NAT gateway. This design still incurs costs (EC2, interface endpoints, observability, logging and storage).

## Architecture

- AWS VPC, private subnet, optional public subnet when NAT or the optional bastion is enabled.
- Private EC2 instance (Ubuntu 24.04), EBS encrypted, metadata v2 required and SSM instance profile.
- VPC interface endpoints: `ssm`, `ssmmessages`, `ec2messages`; S3 gateway endpoint.
- Instance egress limited to endpoint SG and S3 prefix list; optional 443 through NAT.
- Optional restricted SSH bastion disabled by default.
- CloudTrail multi-region, log validation, encrypted/versioned/private S3 logs, VPC Flow Logs and alarm.
- Separate `dev` and `prod` remote state keys.

## Preflight

Tools: Terraform >= 1.10, AWS CLI v2, Session Manager plugin, optional Ansible.

1. Review the AWS account and permissions. This repository does not create or grant administrator access.
2. Bootstrap a **separate state backend** once. The state backend's own Terraform state must be preserved safely and never stored in its own S3 bucket.
3. Confirm the AWS caller: `aws sts get-caller-identity`.
4. Review cloud cost before deploying; default `enable_observability=true` provisions billable resources.

## Backend bootstrap

```bash
cd bootstrap/state-backend
terraform init
terraform apply -var='account_id=123456789012' -var='region=eu-west-3' -var='state_bucket_name=globally-unique-your-state-bucket'
```

Store the bootstrap state securely outside Git and **back it up**. Do not blindly destroy the state bucket.

## Deploy a dev environment

From repository root:

```bash
cp environments/dev/terraform.tfvars.example dev.tfvars
cp environments/dev/backend.tfbackend.example dev.tfbackend
# Edit dev.tfvars and dev.tfbackend. These files are gitignored.
terraform init -backend-config=dev.tfbackend
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
aws ssm start-session --target "$(terraform output -raw private_instance_id)" --region eu-west-3
```

For prod use a *separate checkout/workspace directory* and prod backend configuration. Do not switch backends casually in one shared working directory. Use separate approvals, roles and ideally AWS accounts.

## Operations & known limitations

- **No NAT by default**: SSM connects over VPC endpoints. `apt` cannot contact public Ubuntu repositories; enable optional NAT for outbound HTTPS, or provide an internal package mirror/immutable patched AMI. A NAT gateway carries ongoing charges.
- Interface endpoints incur ongoing hourly/data charges; select endpoints for the region/account and check current support.
- Bastion is *opt-in*, requires an existing key pair and a single trusted `/32`. Its SSH key must be managed off-repository; no public SSH by default.
- The private workload has no inbound service port. Add a **separate reviewed SG ingress and load balancer** for any actual application, rather than opening SSH or blanket ingress.
- SSM Agent must be available in the selected AMI; verify managed-node registration before disabling SSH with Ansible.
- `ansible/playbook.yml` is manual: connect over a trusted channel (SSM or temporary bastion), and test on dev before applying.
- CloudTrail S3 object data events are opt-in and billable via `audit_s3_bucket_arns`. S3 log bucket policies and KMS permissions should be verified with an AWS smoke test.
- Single AZ and single instance **do not provide high availability**, immutable deployment or disaster recovery. Production requires multiple AZs, backups/restore testing, capacity planning and documented RTO/RPO.
- Provider lockfile `.terraform.lock.hcl` should be generated with `terraform init -backend=false` and **committed**. No provider download was possible during this authoring session.
- Deploy workflow generates a plan only. Approval, AWS OIDC trust policies and branch protection require administrator setup. Never auto-apply from untrusted PRs.
- CI scanners may flag deliberate optional bastion/NAT paths; review and document precise exceptions rather than disabling all checks.

## Security controls & threat model

| Threat | Control | Verification |
|---|---|---|
| Stolen instance metadata credentials | IMDSv2, hop limit 1, least-privilege SSM role | EC2 `DescribeInstances` metadata options |
| SSH scanning / credential stuffing | No public SSH, SSM PrivateLink | SG ingress and SSM session test |
| EBS theft | Encrypted gp3 root volume | `DescribeVolumes` |
| State exfiltration | Private versioned S3 bucket, SSE, TLS enforcement, lockfile | S3 public access, versioning and denied unauthorized access |
| Overprivileged automation | GitHub OIDC short-lived AWS credentials, scoped roles and manual deployment | STS caller + IAM audit |
| Configuration errors | Terraform validation, Trivy/Checkov CI | Intentionally failing insecure test configuration |
| Untracked changes | CloudTrail and VPC Flow Logs | Generate events and check log delivery |

## Validation status

Files have been statically reviewed. **No live AWS apply, SSM session, Terraform provider init/validate, Ansible execution, or GitHub Actions run has been verified here**. A successful pipeline and real environment smoke test remain release gates.

## Cost / teardown

Use `terraform plan -destroy` and review carefully, then `terraform destroy -var-file=dev.tfvars`. Audit log buckets have deletion protection (`force_destroy = false`) so they are intentionally not automatically emptied. Back up or retain evidence and follow a separate, approved log-retention procedure; never silently remove the audit trail.
