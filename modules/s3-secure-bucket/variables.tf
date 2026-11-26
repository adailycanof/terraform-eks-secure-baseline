variable "name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Bucket name must be 3-63 chars of lowercase letters, digits, dots and hyphens."
  }
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN. If null, a dedicated CMK with rotation is created."
  type        = string
  default     = null
}

variable "access_log_bucket" {
  description = "Bucket that receives server access logs. Null disables logging."
  type        = string
  default     = null
}

variable "noncurrent_version_days" {
  description = "Days to keep noncurrent object versions."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket. Keep false outside sandboxes."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
