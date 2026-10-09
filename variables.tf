variable "aws_region" {
  description = "Deployment region."
  type        = string
  default     = "eu-west-3"
}

variable "aws_account_id" {
  description = "Expected 12-digit AWS account; prevents wrong-account deployments."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "environment" {
  description = "Short environment identifier."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "availability_zone" {
  description = "Single-AZ template; production HA needs more than one instance and zone."
  type        = string
  default     = "eu-west-3a"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  description = "Optional pinned Ubuntu 24.04 AMI; null uses Canonical's public SSM parameter."
  type        = string
  default     = null
}

variable "enable_nat_gateway" {
  description = "Optional internet egress for apt updates/external APIs; NAT incurs hourly and data costs."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Off by default; use SSM Session Manager."
  type        = bool
  default     = false
}

variable "bastion_allowed_cidr" {
  description = "Single trusted IPv4 /32; required when enable_bastion is true."
  type        = string
  default     = null

  validation {
    condition     = var.bastion_allowed_cidr == null ? true : (can(cidrhost(var.bastion_allowed_cidr, 0)) && endswith(var.bastion_allowed_cidr, "/32"))
    error_message = "bastion_allowed_cidr must be a valid IPv4 /32."
  }
}

variable "bastion_key_name" {
  description = "Existing EC2 key-pair name for optional bastion; do not commit the private key."
  type        = string
  default     = null
}

variable "enable_observability" {
  description = "CloudTrail, VPC Flow Logs, and an alert (billable)."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Optional SNS alarm email; confirmation required."
  type        = string
  default     = null
}

variable "audit_s3_bucket_arns" {
  description = "S3 bucket ARNs for billable CloudTrail object data events."
  type        = list(string)
  default     = []
}
