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
}
