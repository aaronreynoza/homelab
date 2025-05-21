variable "proxmox_api_url" {
  description = "The URL of the Proxmox API"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_id" {
  description = "The token ID for Proxmox API authentication"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "The token secret for Proxmox API authentication"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "The name of the Proxmox node to create resources on"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for container access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key for provisioning"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vpn_server_ip" {
  description = "The public IP of the WireGuard VPN server"
  type        = string
}

variable "vpn_cidr" {
  description = "CIDR block for the VPN network"
  type        = string
  default     = "10.10.10.0/24"
}

variable "proxmox_local_ip" {
  description = "Local IP of your Proxmox server for VPN access"
  type        = string
  default     = "10.10.10.2/32"
}
