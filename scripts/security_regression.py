#!/usr/bin/env python3
"""Dependency-free static security preflight; no AWS or GitHub Actions calls."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
total = 0

def load(path):
    return (ROOT / path).read_text(encoding="utf-8")

def assert_control(label, good):
    global total
    total += 1
    if not good:
        errors.append(label)

def has(path, pattern):
    return bool(re.search(pattern, load(path), re.M | re.S))

def balanced_hcl(text):
    # Strip double-quoted HCL strings before comments so URLs and # stay inert.
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'(?m)(?:#|//).*$', '', text)
    stack = []
    close = {'}': '{', ']': '[', ')': '('}
    for char in text:
        if char in "{[(":
            stack.append(char)
        elif char in "}])":
            if not stack or stack.pop() != close[char]:
                return False
    return not stack

network = load("modules/network/main.tf")
compute = load("modules/compute/main.tf")
root = load("main.tf")
audit = load("modules/observability/main.tf")
state = load("bootstrap/state-backend/main.tf")
ci = load(".github/workflows/terraform-ci.yml")
ansible = load("ansible/roles/base-hardening/tasks/main.yml")

def unrestricted_ingress():
    # SG egress to 0.0.0.0/0 is a separate, documented NAT choice.
    for path in ROOT.rglob("*.tf"):
        if ".terraform" in path.parts:
            continue
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(
            r'(?ms)^resource\s+"aws_vpc_security_group_ingress_rule"\s+"[^"]+"\s*\{(.*?)^\}',
            source,
        ):
            block = match.group(1)
            if re.search(r'cidr_ipv4\s*=\s*"0\.0\.0\.0/0"', block) or re.search(r'cidr_ipv6\s*=\s*"::/0"', block):
                return True
    return False

assert_control("No unrestricted IPv4/IPv6 security group ingress", not unrestricted_ingress())

assert_control("No VPC-wide access to SSM endpoints", 'cidr_ipv4         = var.vpc_cidr' not in network)
assert_control("SSM ingress is scoped to workload SG", 'referenced_security_group_id = module.compute.workload_security_group_id' in root)
assert_control("SSM ingress is scoped to optional bastion SG", 'referenced_security_group_id = module.compute.bastion_security_group_id' in root)
assert_control("Workload private IP only", 'associate_public_ip_address = false' in compute)
assert_control("IMDSv2 required for both EC2 instances", compute.count('http_tokens                 = "required"') >= 2)
assert_control("All EC2 root volumes encrypted", compute.count('encrypted             = true') >= 2)
assert_control("EC2 volumes deleted on termination", compute.count('delete_on_termination = true') >= 2)
assert_control("Bastion ingress is opt-in", 'resource "aws_vpc_security_group_ingress_rule" "bastion_ssh"' in compute and 'count             = var.enable_bastion ? 1 : 0' in compute)
assert_control("Bastion disabled by default", has("variables.tf", r'variable "enable_bastion" \{[^}]*default\s*=\s*false'))
assert_control("NAT disabled by default", has("variables.tf", r'variable "enable_nat_gateway" \{[^}]*default\s*=\s*false'))
assert_control("Remote state lockfile required", 'use_lockfile = true' in load("versions.tf"))
assert_control("State is versioned", 'status = "Enabled"' in state)
assert_control("State bucket public access blocked", 'block_public_acls       = true' in state and 'restrict_public_buckets = true' in state)
assert_control("State bucket deletion protected", 'prevent_destroy = true' in state)
assert_control("State bucket uses customer-managed KMS encryption", 'kms_master_key_id = aws_kms_key.state.arn' in state)
assert_control("CloudTrail multi-region and log integrity", 'is_multi_region_trail         = true' in audit and 'enable_log_file_validation    = true' in audit)
assert_control("CloudTrail log bucket deletion protected", 'prevent_destroy = true' in audit)
assert_control("CloudTrail has a KMS key", 'kms_key_id                    = aws_kms_key.logs.arn' in audit)
assert_control("CloudTrail Bucket Keys have a dedicated decrypt permission", 'Sid       = "CloudTrailBucketKeyDecrypt"' in audit and 'Action    = "kms:Decrypt"' in audit)
assert_control("CloudTrail KMS GenerateDataKey remains ARN scoped", '"aws:SourceArn" = "arn:aws:cloudtrail:' in audit)
assert_control("Production requires a confirmed alert destination", 'var.environment != "prod" || (var.enable_observability && can(regex("@", var.alert_email)))' in load("variables.tf"))
assert_control("OIDC workflow restricted to main", "if: github.ref == 'refs/heads/main'" in load(".github/workflows/deploy.yml"))
assert_control("SSHD candidate configuration is validated before replacement", 'validate: "/usr/sbin/sshd -t -f %s"' in ansible)
assert_control("CloudTrail tampering alarm", '"StopLogging", "DeleteTrail", "UpdateTrail"' in audit)
assert_control("SNS alerts encrypted", 'kms_master_key_id = aws_kms_key.alarms.arn' in audit)
assert_control("SSM session required before SSH shutdown", 'hardening_confirm_ssm_access | bool' in ansible)
assert_control("Automatic OS security updates configured", 'APT::Periodic::Unattended-Upgrade' in ansible)
assert_control("No automatic Actions on push/PR", 'workflow_dispatch:' in ci and 'pull_request:' not in ci and 'push:' not in ci)
assert_control("Terraform provider lockfile can be committed", '.terraform.lock.hcl' not in [
    line.strip() for line in load(".gitignore").splitlines()
    if line.strip() and not line.startswith("#")
])
assert_control("Terraform state files are gitignored", '*.tfstate' in load(".gitignore"))
for path in sorted(list(ROOT.rglob("*.tf")) + list(ROOT.rglob("*.tftest.hcl"))):
    if ".terraform" not in path.parts:
        assert_control(f"Balanced HCL delimiters in {path.relative_to(ROOT)}", balanced_hcl(path.read_text(encoding="utf-8")))
        assert_control(f"No literal AWS access key in {path.relative_to(ROOT)}", not re.search(r'(?:AKIA|ASIA)[A-Z0-9]{16}', path.read_text(encoding="utf-8")))

for e in errors:
    print("FAIL:", e, file=sys.stderr)
print(f"Offline security preflight: {total - len(errors)}/{total} assertions passed")
print("This is not a replacement for terraform validate, full IaC scanning or an AWS deployment test.")
sys.exit(1 if errors else 0)
