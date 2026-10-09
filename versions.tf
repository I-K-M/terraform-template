terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }

  # Supply bucket, key and region at init time. Never put credentials here.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
