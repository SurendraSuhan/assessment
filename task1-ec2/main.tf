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
  region  = var.region
  profile = var.profile
}

module "fleet" {
  source = "./modules/ec2-fleet"

  environment = var.environment
  owner       = var.owner
  subnet_id   = var.subnet_id
  instances   = var.instances
}
