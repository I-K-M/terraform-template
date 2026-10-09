# Secure AWS Terraform Platform

Terraform + Ansible reference deployment for a **private single-AZ EC2 workload** with IAM roles, IMDSv2, encrypted EBS, private SSM connectivity, optional NAT/bastion, CloudTrail and VPC Flow Logs.

This is a demonstration/reference deployment, **not certified production infrastructure**. No AWS resources are deployed by CI. Default deployment has no SSH ingress, no public workload IP and no NAT gateway. This design still incurs costs (EC2, interface endpoints, observability, logging and storage).

## Architecture

- AWS VPC, private subnet, optional public subnet when NAT or the optional bastion is enabled.
- Private EC2 instance (Ubuntu 24.04), EBS encrypted, metadata v2 required and SSM instance profile.
- VPC interface endpoints: `ssm`, `ssmmessages`, `ec2messages`; S3 gateway endpoint.
- Instance egress limited to endpoint SG and S3 prefix list; optional 443 through NAT.
- Optional restricted SSH bastion disabled by default.
- CloudTrail multi-region, log validation, protected encrypted/versioned S3 logs, VPC Flow Logs and KMS-encrypted security alerts.
- EventBridge alarm on CloudTrail logging being stopped, deleted or modified. Verify real event delivery after a test deployment.
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

Store the bootstrap state securely outside Git and **back it up**. Do not blindly destroy the state bucket. Record the `kms_key_arn` output and add it to your `.tfbackend` file. Restrict S3 and KMS permissions to environment-specific deployment roles (see `docs/state-iam-policy.example.json`).

## Deploy a dev environment

From repository root:

```bash
cp environments/dev/terraform.tfvars.example dev.tfvars
cp environments/dev/backend.tfbackend.example dev.tfbackend
# Edit dev.tfvars and dev.tfbackend, including kms_key_id. These files are gitignored.
terraform init -backend-config=dev.tfbackend
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
aws ssm start-session --target "$(terraform output -raw private_instance_id)" --region eu-west-3
```

For prod use a *separate checkout/workspace directory* and prod backend configuration. Do not switch backends casually in one shared working directory. Use separate approvals, roles and ideally AWS accounts.

## Free local security checks (no GitHub Actions)

```bash
make offline-check          # Python standard library only; no AWS or network
make terraform-check        # Terraform fmt, init (provider download), validate and tests
make scan                   # Trivy IaC scan; requires local Trivy installation
```

The GitHub workflow `terraform-ci.yml` is **manual-only**. Push and merge do not trigger it. The `deploy.yml` workflow also only supports manual plan generation and never applies resources.

## Operations & known limitations

- **No NAT by default**: SSM connects over VPC endpoints. `apt` cannot contact public Ubuntu repositories; enable optional NAT for outbound HTTPS, or provide an internal package mirror/immutable patched AMI. A NAT gateway carries ongoing charges.
- Interface endpoints incur ongoing hourly/data charges; select endpoints for the region/account and check current support.
- Bastion is *opt-in*, requires an existing key pair and a single trusted `/32`. Its SSH key must be managed off-repository; no public SSH by default.
- The private workload has no inbound service port. Add a **separate reviewed SG ingress and load balancer** for any actual application, rather than opening SSH or blanket ingress.
- SSM Agent must be available in the selected AMI; verify managed-node registration before disabling SSH with Ansible.
- `ansible/playbook.yml` is manual: connect over a trusted channel (SSM or temporary bastion), and test on dev before applying. SSH is not stopped automatically. Disabling SSH requires `hardening_disable_ssh=true` and a separate explicit `hardening_confirm_ssm_access=true` after verifying an independent SSM session.
- The VPC endpoints only admit connections from EC2 security groups managed by this template; private EC2 has no public IP. No workload application port is open by default.
- CloudTrail S3 object data events are opt-in and billable via `audit_s3_bucket_arns`. S3 log bucket policies and KMS permissions should be verified with an AWS smoke test.
- Single AZ and single instance **do not provide high availability**, immutable deployment or disaster recovery. Production requires multiple AZs, backups/restore testing, capacity planning and documented RTO/RPO.
- The provider lockfile `.terraform.lock.hcl` is not yet committed; generate it with `terraform init -backend=false`, check provider checksum sources and commit it. Do not invent lockfile checksums.
- Deploy workflow generates a plan only. Approval, AWS OIDC trust policies and branch protection require administrator setup. Never auto-apply from untrusted PRs.
- Static checks are security preflight, not a production guarantee. Confirm KMS/SNS/EventBridge authorization, VPC Flow Logs and IAM trust through a disposable AWS deployment.
- CloudTrail audit S3 and state bucket have `prevent_destroy`; changing/removing these resources needs an explicit retention review. KMS keys have a deletion waiting period.
- SNS/CloudTrail anti-tamper notifications require SNS subscription confirmation; without a recipient and delivery test, they are not an effective alerting system.

## Security controls & threat model

| Threat | Control | Verification |
|---|---|---|
| Stolen instance metadata credentials | IMDSv2, hop limit 1, least-privilege SSM role | EC2 `DescribeInstances` metadata options |
| SSH scanning / credential stuffing | No public SSH, SSM PrivateLink | SG ingress and SSM session test |
| EBS theft | Encrypted gp3 root volume | `DescribeVolumes` |
| State exfiltration | Private versioned S3 bucket, customer-managed KMS, TLS enforcement, lockfile | S3 public access, KMS access and unauthorized state read test |
| Overprivileged automation | GitHub OIDC short-lived AWS credentials, scoped roles and manual deployment | STS caller + IAM audit |
| Configuration errors | Terraform validation, Trivy/Checkov CI | Intentionally failing insecure test configuration |
| Untracked changes | CloudTrail, VPC Flow Logs and EventBridge anti-tamper alerts | Generate test events and verify SNS delivery |

## Validation status

Static source-level safeguards are provided in `scripts/security_regression.py`. Local Terraform provider validation, actual cloud integration tests, Ansible execution, KMS delivery and IAM access controls still need an authorized deployment test. This repository has not been deployed to AWS as part of this change. See `docs/security-model.md` and `docs/deployment-validation.md`.

## Cost / teardown

Use `terraform plan -destroy` and review carefully, then `terraform destroy -var-file=dev.tfvars`. Audit log buckets have deletion protection (`force_destroy = false`) so they are intentionally not automatically emptied. Back up or retain evidence and follow a separate, approved log-retention procedure; never silently remove the audit trail.
