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

variable "account_b_id" {
  type    = string
  default = "111111111111"
}

# ---------------------------------------------------------------- group1
# CLI / programmatic only: users get NO login profile (no console password).
resource "aws_iam_group" "group1" {
  name = "group1"
}

resource "aws_iam_user" "engine" {
  name = "engine"
}

resource "aws_iam_user" "ci" {
  name = "ci"
}

resource "aws_iam_group_membership" "group1" {
  name  = "group1-membership"
  group = aws_iam_group.group1.name
  users = [aws_iam_user.engine.name, aws_iam_user.ci.name]
}

# Access keys are intentionally NOT created in Terraform (the secret would land in state).
# Create out-of-band:  aws iam create-access-key --user-name ci

# ---------------------------------------------------------------- group2
# Console + CLI.
resource "aws_iam_group" "group2" {
  name = "group2"
}

resource "aws_iam_user" "alice" {
  name = "alice"
}

resource "aws_iam_user" "bob" {
  name = "bob"
}

resource "aws_iam_user_login_profile" "alice" {
  user                    = aws_iam_user.alice.name
  password_reset_required = true
}

resource "aws_iam_user_login_profile" "bob" {
  user                    = aws_iam_user.bob.name
  password_reset_required = true
}

resource "aws_iam_group_membership" "group2" {
  name  = "group2-membership"
  group = aws_iam_group.group2.name
  users = [aws_iam_user.alice.name, aws_iam_user.bob.name]
}

# Let group2 members change their own password / manage MFA (needed for the console flow).
resource "aws_iam_group_policy_attachment" "group2_change_password" {
  group      = aws_iam_group.group2.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

resource "aws_iam_group_policy" "group2_self_mfa_and_assume" {
  name  = "self-manage-mfa-and-assume-roleA"
  group = aws_iam_group.group2.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageOwnMFA"
        Effect = "Allow"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ResyncMFADevice",
          "iam:DeactivateMFADevice",
          "iam:DeleteVirtualMFADevice",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices"
        ]
        Resource = [
          "arn:aws:iam::*:mfa/*",
          "arn:aws:iam::*:user/$${aws:username}"
        ]
      },
      {
        Sid      = "AssumeRoleA"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.roleA.arn
      }
    ]
  })
}

# ---------------------------------------------------------------- roleA
# Admin on everything EXCEPT IAM. Assumable by group2 users, MFA required.
data "aws_iam_policy_document" "roleA_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.alice.arn, aws_iam_user.bob.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "roleA" {
  name               = "roleA"
  assume_role_policy = data.aws_iam_policy_document.roleA_trust.json
}

resource "aws_iam_role_policy" "roleA_admin_except_iam" {
  name = "admin-except-iam"
  role = aws_iam_role.roleA.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect      = "Allow"
      NotAction   = "iam:*"
      Resource    = "*"
    }]
  })
}

# ---------------------------------------------------------------- roleB
# Only permission: assume roleC in Account B.
data "aws_iam_policy_document" "roleB_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.ci.arn, aws_iam_user.engine.arn]
    }
  }
}

resource "aws_iam_role" "roleB" {
  name               = "roleB"
  assume_role_policy = data.aws_iam_policy_document.roleB_trust.json
}

resource "aws_iam_role_policy" "roleB_assume_roleC" {
  name = "assume-roleC-only"
  role = aws_iam_role.roleB.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.account_b_id}:role/roleC"
    }]
  })
}

output "roleB_arn" {
  value = aws_iam_role.roleB.arn
}
