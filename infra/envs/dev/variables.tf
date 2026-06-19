variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name of the project to be used in resource naming"
  type        = string
  default     = "event-driven-observability-platform"
}

variable "alerts_email" {
  description = "Email that will receive alerts from SNS"
  type        = string

  validation {
    condition     = length(trimspace(var.alerts_email)) > 0
    error_message = "alerts_email must be a non-empty email address."
  }
}

variable "ingestion_alias_function_version" {
  description = "Optional Lambda version for the ingestion alias. When null, the alias points to the latest published version."
  type        = string
  default     = null
}
