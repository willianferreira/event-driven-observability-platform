output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket used to store Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_bucket_name" {
  description = "Name of the S3 bucket used to store Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "plan_role_arn" {
  description = "IAM role ARN for GitHub Actions Terraform plan"
  value       = aws_iam_role.github_actions_plan.arn
}

output "apply_role_arn" {
  description = "IAM role ARN for GitHub Actions Terraform apply"
  value       = aws_iam_role.github_actions_apply.arn
}
