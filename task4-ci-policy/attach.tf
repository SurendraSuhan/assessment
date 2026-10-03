# Attaches the custom policy to the `ci` user created in task3-iam/account-a.
# Apply AFTER task3-iam/account-a.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-south-1"
  profile = "account_a"
}

resource "aws_iam_user_policy" "ci" {
  name   = "ci-pipeline-least-privilege"
  user   = "ci"
  policy = file("${path.module}/ci-policy.json")
}
