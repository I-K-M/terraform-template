variable "name_prefix" { type = string }
variable "region" { type = string }
variable "aws_account_id" { type = string }
variable "vpc_id" { type = string }
variable "alert_email" { type = string }
variable "audit_s3_bucket_arns" { type = list(string) }
