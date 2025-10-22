variable "pm_node" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "talos_image_url" {
  type = string
}

variable "talos_image_file_name" {
  type = string
}

variable "PROXMOX_DIR_STORAGE" {
  type = string
  description = "Name of the directory storage in Proxmox (e.g., local)"
}
