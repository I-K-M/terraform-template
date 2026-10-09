# Deployment evidence checklist

Deployment is **not** completed by the presence of code alone. Collect redacted evidence after a test deployment:

1. `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`; record Terraform and AWS provider versions.
2. Plan only the intended account (`aws sts get-caller-identity`) and backend state key.
3. Confirm private EC2 has no public IP, IMDSv2 is required and root EBS is encrypted.
4. Confirm workload SG inbound rules are empty by default, egress is restricted, and private subnet has no IGW route.
5. Start SSM session; verify that a private EC2 agent reports online with no NAT.
6. Validate CloudTrail delivery with the SSE-KMS S3 Bucket Key configuration (the CloudTrail KMS key must allow the service `kms:Decrypt`), VPC Flow Logs delivery, SNS subscription confirmation and a sample EventBridge tamper alert. Check CloudTrail/KMS delivery errors, not just resource creation.
7. Run `make offline-check`, `make terraform-check`, `make scan`. Test bad configuration: unrestricted SSH or IMDSv1 must be rejected. Confirm no automated Actions executions on PR/push.
8. Terraform second plan should show no drift after settling.
9. Run OS/Ansible hardening with an approved recovery path; confirm SSM still works.
10. Document cost, rollback, restore and incident contacts.

Never commit the resulting state, plan files or credential evidence.
