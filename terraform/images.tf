resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  node_name    = var.pm_node
  datastore_id = var.datastore_id
  content_type = "disk-image"
  url          = var.talos_image_url
  file_name    = var.talos_image_file_name
  overwrite    = true
}

output "talos_image_file_id" {
  value = proxmox_virtual_environment_download_file.talos_nocloud_image.id
}
