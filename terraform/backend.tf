terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox" 
      version = ">= 2.9.0, < 4.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
  required_version = ">= 1.5.0"
}
