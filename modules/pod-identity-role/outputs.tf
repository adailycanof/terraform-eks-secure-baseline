output "role_arn" {
  description = "Workload role ARN."
  value       = aws_iam_role.this.arn
}
