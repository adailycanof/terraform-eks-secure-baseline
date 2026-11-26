output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "artifacts_bucket" {
  description = "Encrypted artifacts bucket."
  value       = module.artifacts_bucket.bucket_id
}

output "github_deploy_role_arn" {
  description = "Role for aws-actions/configure-aws-credentials."
  value       = module.github_deploy_role.role_arn
}
