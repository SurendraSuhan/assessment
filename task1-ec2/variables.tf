variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "profile" {
  type    = string
  default = "account_a"
}

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
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    iops          = optional(number)
    key_name      = string
    protected     = optional(bool, false)
  }))
}
