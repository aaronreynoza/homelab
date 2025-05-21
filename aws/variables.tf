variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for the instance"
  type        = string
}

variable "proxmox_local_ip" {
  description = "Local IP of your Proxmox server for VPN access"
  type        = string
  default     = "10.10.10.2/32"
}

variable "vpn_cidr" {
  description = "CIDR block for the VPN network"
  type        = string
  default     = "10.10.10.0/24"
}
