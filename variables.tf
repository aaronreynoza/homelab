variable "proxmox_url" {
  description = "URL of the Proxmox server"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox API username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "plex_version" {
  description = "Plex version to install"
  type        = string
  default     = "latest"
}
