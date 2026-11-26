variable "role_name" {
  description = "IAM role name assumed by GitHub Actions."
  type        = string
}

variable "allowed_subjects" {
  description = "OIDC `sub` patterns allowed to assume the role, e.g. repo:org/repo:environment:prod."
  type        = list(string)

  validation {
    condition     = length(var.allowed_subjects) > 0 && alltrue([for s in var.allowed_subjects : startswith(s, "repo:") && s != "repo:*"])
    error_message = "Provide at least one subject, each scoped to a repo (repo:<org>/<repo>:...). Wildcard-everything is not allowed."
  }
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider (only one per account)."
  type        = bool
  default     = true
}

variable "managed_policy_arns" {
  description = "Managed policies to attach."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional least-privilege inline policy."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary that caps what the CI role can ever do."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
