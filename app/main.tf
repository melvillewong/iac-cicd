terraform {
  required_version = "~> 1.15.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # backend "s3" {}
}

provider "aws" {
  region = var.region
}

resource "aws_ssm_parameter" "message" {
  name  = "/iac/app-message"
  value = var.app_message
  type  = "String"
}
