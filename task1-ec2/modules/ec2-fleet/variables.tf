variable "environment" {
  type = string
}

variable "owner" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instances" {
  description = "Single source of truth: map of instance name => settings."
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    iops          = optional(number) # required for io1/io2
    key_name      = string
    protected     = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["gp2", "gp3", "io1", "io2", "standard"], v.volume_type)
    ])
    error_message = "Root volume_type must be one of gp2, gp3, io1, io2, standard (st1/sc1 cannot be root volumes)."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      !contains(["io1", "io2"], v.volume_type) || v.iops != null
    ])
    error_message = "io1/io2 volumes require 'iops'."
  }
}
