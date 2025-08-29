provider "proxmox" {
  endpoint = "https://REDACTED_IP:8006/"
  insecure = true # Only needed if your Proxmox server is using a self-signed certificate
}