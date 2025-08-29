variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "default_gateway" {
  type    = string
  default = "192.168.1.1" // <IP address of your default gateway
}

variable "talos_cp_01_ip_addr" {
  type    = string
  default = "192.168.1.150" // <an unused IP address in your network>
}

variable "talos_worker_01_ip_addr" {
  type    = string
  default = "192.168.1.151" // <an unused IP address in your network>
}

variable "talos_worker_02_ip_addr" {
  type    = string
  default = "192.168.1.152" // <an unused IP address in your network>
}