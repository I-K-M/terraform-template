variable "region" { type = string }
variable "account_id" {
  type = string
  validation {
    condition = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Expected 12 digit account ID."
  }
}
variable "state_bucket_name" {
  type = string
  description = "Globally unique name. NEVER use this backend to manage its own state."
}
