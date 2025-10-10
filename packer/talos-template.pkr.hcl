// Packer template to create a Talos VM template on Proxmox (username/password auth)

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.1.5"
    }
  }
}

variable "proxmox_url" {
  type = string
}
variable "proxmox_username" {
  type = string
}
variable "proxmox_password" {
  type = string
  sensitive = true
}
variable "proxmox_node" {
  type = string
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}
variable "template_name" {
  type    = string
  default = "template-talos"
}
variable "talos_version" {
  type    = string
  default = "v1.7.4"
}
variable "talos_image_url" {
  type    = string
  // default matches v1.7.4; override via workflow var if needed
  default = "https://github.com/siderolabs/talos/releases/download/v1.7.4/nocloud-amd64.img.xz"
}
variable "vm_cores" {
  type    = number
  default = 2
}
variable "vm_memory" {
  type    = number
  default = 4096
}
variable "vm_disk_gb" {
  type    = number
  default = 8
}

source "proxmox" "talos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true

  node    = var.proxmox_node
  vm_name = "${var.template_name}-${var.talos_version}"

  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  // Upload Talos NoCloud disk image and attach it as the VM disk
  disks {
    type            = "scsi"
    storage_pool    = var.storage_pool
    disk_size       = "${var.vm_disk_gb}G"
    disk_image_url  = var.talos_image_url
  }

  cores           = var.vm_cores
  memory          = var.vm_memory
  scsi_controller = "virtio-scsi-pci"
  bios            = "seabios"

  // Add Cloud-Init drive so clones can inject per-node config
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  // Convert built VM to template
  convert_to_template = true
}

build {
  name    = "talos-template"
  sources = ["source.proxmox.talos"]

  provisioner "shell" {
    inline = ["echo Talos template ready"]
  }
}
