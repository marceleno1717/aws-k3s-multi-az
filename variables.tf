variable "ami" {
  type      = string
  const     = true
  default   = "ami-0e207c18bb303cc68"
  sensitive = false
}

variable "key_pair_name" {
  type      = string
  const     = true
  default   = "k3s"
  sensitive = false
}

variable "manager_instance_type" {
  type      = string
  const     = true
  default   = "t3.small"
  sensitive = false
}

variable "worker_instance_type" {
  type      = string
  const     = true
  default   = "t3.micro"
  sensitive = false
}

variable "lb_ip" {
  type      = string
  const     = true
  default   = "13.36.128.78"
  sensitive = false
}

data "http" "public_ip" {
  url = "https://wtfismyip.com/text"
}
