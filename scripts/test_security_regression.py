"""Run without AWS credentials, Terraform, GitHub Actions or third-party packages."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class SecurityRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tf-security-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        shutil.copytree(
            SOURCE,
            self.root,
            ignore=shutil.ignore_patterns(".git", ".terraform", "__pycache__", "*.pyc", "*.tfstate*", "*.tfplan"),
        )

    def run_preflight(self):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/security_regression.py")],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )

    def mutate(self, path, expected, replacement):
        file = self.root / path
        before = file.read_text(encoding="utf-8")
        self.assertIn(expected, before, f"Test fixture changed: {path}")
        file.write_text(before.replace(expected, replacement, 1), encoding="utf-8")

    def assert_rejected(self):
        result = self.run_preflight()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FAIL:", result.stderr)

    def test_clean_configuration_passes(self):
        result = self.run_preflight()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_public_ingress_is_rejected(self):
        path = "main.tf"
        file = self.root / path
        file.write_text(file.read_text(encoding="utf-8") + '''
resource "aws_vpc_security_group_ingress_rule" "insecure_test" {
  security_group_id = "sg-test"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}
''', encoding="utf-8")
        self.assert_rejected()

    def test_imdsv1_downgrade_is_rejected(self):
        self.mutate("modules/compute/main.tf", 'http_tokens                 = "required"', 'http_tokens                 = "optional"')
        self.assert_rejected()

    def test_cloudtrail_decrypt_removal_is_rejected(self):
        self.mutate("modules/observability/main.tf", 'Sid       = "CloudTrailBucketKeyDecrypt"', 'Sid       = "NoCloudTrailDecrypt"')
        self.assert_rejected()

    def test_ci_push_trigger_is_rejected(self):
        self.mutate(".github/workflows/terraform-ci.yml", "on:\n  workflow_dispatch:", "on:\n  push:\n  workflow_dispatch:")
        self.assert_rejected()

    def test_ssh_lockout_guard_removal_is_rejected(self):
        self.mutate("ansible/roles/base-hardening/tasks/main.yml", "hardening_confirm_ssm_access | bool", "true")
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
