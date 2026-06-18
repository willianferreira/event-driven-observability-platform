variable "bucket_name" {
  description = "Globally unique S3 bucket name used to store Terraform state"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name using lowercase letters, numbers, dots, or hyphens."
  }
}

variable "environment" {
  description = "Environment name used for tagging bootstrap resources"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for tagging bootstrap resources"
  type        = string
  default     = "event-driven-observability-platform"
}

variable "region" {
  description = "AWS region where bootstrap resources will be created"
  type        = string
  default     = "us-east-2"
}
