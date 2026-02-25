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
  type = string
  default = "willianforbusiness@gmail.com"
}