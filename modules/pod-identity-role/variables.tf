variable "role_name" {
  description = "IAM role name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_arn" {
  description = "EKS cluster ARN (used to stop confused-deputy use from other clusters)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID that owns the cluster."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount."
  type        = string
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name."
  type        = string
}

variable "policy_json" {
  description = "Least-privilege IAM policy for the workload."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
