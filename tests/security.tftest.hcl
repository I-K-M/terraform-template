# Native plan tests use provider mocking; run terraform test after provider initialization.
mock_provider "aws" {}

run "secure_defaults" {
  command = plan
  variables {
    aws_account_id       = "123456789012"
    environment          = "dev"
    ami_id               = "ami-0123456789abcdef0"
    enable_observability = false
  }
  assert {
    condition     = module.compute.bastion_public_ip == null
    error_message = "The bastion must be absent by default."
  }

  assert {
    condition     = module.compute.workload_public_ip_enabled == false
    error_message = "Workload must never receive a public IPv4 address."
  }

  assert {
    condition     = module.compute.workload_imdsv2_required == "required"
    error_message = "EC2 must reject IMDSv1."
  }

  assert {
    condition     = module.compute.workload_ebs_encrypted == true
    error_message = "Root volume encryption must be enabled."
  }
}
