data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Both sets come from the SAME variable. They are split only because
  # `prevent_destroy` must be a literal and cannot vary per for_each item.
  protected_instances = { for k, v in var.instances : k => v if v.protected }
  standard_instances  = { for k, v in var.instances : k => v if !v.protected }

  common_tags = {
    Environment = var.environment
    Owner       = var.owner
  }
}

resource "aws_instance" "standard" {
  for_each = local.standard_instances

  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = each.value.instance_type
  key_name      = each.value.key_name
  subnet_id     = var.subnet_id

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = each.value.iops
  }

  tags = merge(local.common_tags, { Name = each.key })
}

resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami                     = data.aws_ssm_parameter.al2023.value
  instance_type           = each.value.instance_type
  key_name                = each.value.key_name
  subnet_id               = var.subnet_id
  disable_api_termination = true # also blocks console/CLI termination

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = each.value.iops
  }

  tags = merge(local.common_tags, { Name = each.key })

  lifecycle {
    prevent_destroy = true # blocks `terraform destroy` and forced replacement
  }
}

locals {
  all_instances = merge(aws_instance.standard, aws_instance.protected)
}
