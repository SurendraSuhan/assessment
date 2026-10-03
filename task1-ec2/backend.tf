# Task 2. Backend blocks cannot use variables, so values are literal.
# Create the bucket/table first with ../task2-remote-state, then:
#   terraform init -migrate-state
terraform {
  backend "s3" {
    bucket         = "REPLACE-ME-myorg-tfstate-000000000000"
    key            = "task1-ec2/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "account_a"
  }
}
