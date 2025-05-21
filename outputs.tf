output "plex_ip" {
  description = "IP address of the Plex container"
  value       = proxmox_container.plex.ip_address
}

output "plex_container_id" {
  description = "ID of the Plex container"
  value       = proxmox_container.plex.id
}
