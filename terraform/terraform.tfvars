pm_node            = "pve"
vm_storage         = "local-lvm"
bridge             = "vmbr0"
pm_ssh_host        = "root@REDACTED_IP"

ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO9K8RJ1diDqnBf1CVNQGR+l9RVyxc8Ka710weX/QBve aaron@reynoza.org"

# Optional override; leave empty to auto-download from SideroLabs
talos_version  = "v1.7.5"
talos_image_url = "" # keep empty to use the default release URL

cluster_name     = "talos"
cluster_endpoint = "https://192.168.100.101:6443"

template_vmid  = 9000
template_name  = "talos-template"

nodes = {
  w1 = { memory = 8192, cores = 4, os_disk = "20G", data_disk = "500G" }
  w2 = { memory = 8192, cores = 4, os_disk = "20G", data_disk = "500G" }
}

proxmox_api_url          = "https://REDACTED_IP:8006/api2/json"
proxmox_api_token_secret = "c3c416bb-dd9d-426e-bcc4-17f25acf8676"
