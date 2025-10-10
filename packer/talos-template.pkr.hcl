// Build a Talos VM TEMPLATE on Proxmox using the hashicorp/proxmox plugin.
// It boots a small VM from the Talos ISO and marks it as a template.
// Per-node configs are added later via Cloud-Init when Terraform clones it.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

variable "proxmox_url"       { type = string }
variable "proxmox_username"  { type = string }
variable "proxmox_password"  { type = string sensitive = true }
variable "proxmox_node"      { type = string }

variable "storage_pool"      { type = string  default = "local-lvm" }
variable "network_bridge"    { type = string  default = "vmbr0" }

variable "template_name"     { type = string  default = "template-talos" }
variable "talos_version"     { type = string  default = "v1.7.4" }

// Use the official Talos ISO with the proxmox-iso builder.
variable "talos_iso_url" {
  type    = string
  default = "https://github.com/siderolabs/talos/releases/download/v1.7.4/metal-amd64.iso"
}

// Optional checksum (leave blank to skip verification)
variable "talos_iso_checksum" {
  type    = string
  default = "" // e.g., "sha256:<hash>"
}

variable "vm_cores"   { type = number default = 2 }
variable "vm_memory"  { type = number default = 4096 }
variable "vm_disk_gb" { type = number default = 8 }

source "proxmox-iso" "talos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_s_
