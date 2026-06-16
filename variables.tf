variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "app_message" {
  description = "AWS param value"
  type        = string
  default     = "hello AWS"
}
