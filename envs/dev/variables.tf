variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "dso-dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.40.0.0/16"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Empty = private endpoint only."
  type        = list(string)
  default     = []
}

variable "github_subjects" {
  description = "GitHub OIDC subjects allowed to deploy, e.g. repo:my-org/my-app:environment:dev."
  type        = list(string)
  default     = ["repo:example-org/example-app:environment:dev"]
}

variable "admin_role_arns" {
  description = "IAM roles granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}
