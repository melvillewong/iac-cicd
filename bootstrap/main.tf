terraform {
  required_version = "~> 1.15.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_openid_connect_provider" "default" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.default.arn] # OIDC provider ARN, as list; reference = implicit dependency, TF builds provider first
    }
    actions = ["sts:AssumeRoleWithWebIdentity"] # colon not dot; lets a federated (OIDC) identity swap its JWT for temp role creds
    condition {
      test     = "StringEquals"                            # single-value claim; ForAnyValue is for multi-value
      variable = "token.actions.githubusercontent.com:aud" # host prefix = OIDC url minus https://, claim = aud
      values   = ["sts.amazonaws.com"]                     # token minted for AWS STS (matches client_id_list)
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub" # host prefix + sub claim
      values   = ["repo:melvillewong/iac-cicd:*"]          # :* = any ref (branch/PR/tag) in THIS repo may assume role; controls auth scope not triggering; tighten later e.g. :ref:refs/heads/main
    }
  }
}


resource "aws_iam_role" "default" {
  name               = "github-action-cicd"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "default" {
  name = "cicd-permission"
  role = aws_iam_role.default.id
  policy = jsonencode({    # HCL object -> JSON string (jsondecode is the reverse)
    Version = "2012-10-17" # fixed IAM policy-language date, always this value
    Statement = [
      {
        Action   = ["ssm:GetParameter", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:ListTagsForResource"]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/iac/app-message" # SSM param ARN
      },
      {
        Action   = ["s3:ListBucket"] # bucket-level -> bucket ARN
        Effect   = "Allow"
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] # object-level -> bucket ARN + /*
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      }
    ]
  })
}
