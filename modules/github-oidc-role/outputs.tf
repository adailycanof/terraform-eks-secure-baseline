output "role_arn" {
  description = "ARN to put in aws-actions/configure-aws-credentials `role-to-assume`."
  value       = aws_iam_role.this.arn
}
