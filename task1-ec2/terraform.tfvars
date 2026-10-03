environment = "dev"
owner       = "platform-team"
subnet_id   = "subnet-0123456789abcdef0" # replace

# 5 instances: all different type, volume type, size and key pair.
instances = {
  web-1 = {
    instance_type = "t3.micro"
    volume_type   = "gp3"
    volume_size   = 20
    key_name      = "key-web1"
  }
  web-2 = {
    instance_type = "t3.small"
    volume_type   = "gp2"
    volume_size   = 30
    key_name      = "key-web2"
  }
  app = {
    instance_type = "t3.medium"
    volume_type   = "io1"
    volume_size   = 50
    iops          = 1000
    key_name      = "key-app"
  }
  batch = {
    instance_type = "c5.large"
    volume_type   = "standard" # magnetic; st1/sc1 are not allowed as root
    volume_size   = 40
    key_name      = "key-batch"
  }
  db = {
    instance_type = "r5.large"
    volume_type   = "io2"
    volume_size   = 100
    iops          = 3000
    key_name      = "key-db"
    protected     = true # <- gets prevent_destroy + termination protection
  }
}
