terraform {
  required_version = ">= 1.0.0"
  required_providers {
    proxmox = {
      source  = "telusdigital/proxmox"
      version = "~> 1.0"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.proxmox_url
  pm_user    = var.proxmox_user
  pm_password = var.proxmox_password
  pm_tls_insecure = true
}

# Plex container
resource "proxmox_container" "plex" {
  name = "plex"
  node = var.proxmox_node
  ostemplate = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  storage = "local"
  memory = 2048
  swap = 1024
  cores = 2
  net0 = "name=eth0,bridge=vmbr0,firewall=0,gw=10.0.0.1,ip=10.0.0.100/24,type=veth"
  onboot = true
  startup = "order=1"
  
  # Mounts
  mount {
    source = "/mnt/data/plex"
    target = "/config"
    type = "bind"
  }
  
  mount {
    source = "/mnt/data/media"
    target = "/media"
    type = "bind"
  }
  
  # Container options
  options = [
    "-arch amd64",
    "-hostname plex",
    "-nameserver 1.1.1.1",
    "-nameserver 1.0.0.1"
  ]
}
