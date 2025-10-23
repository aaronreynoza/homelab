locals {
  control_plane_names = ["talos-cp-01"]
  worker_names        = ["talos-worker-01"]
  vm_ids = {
  talos-cp-01      = 500
  talos-worker-01  = 501
  talos-worker-02  = 502
}

  cpu_cores  = 4
  memory_mb  = 16384
  scsihw     = "virtio-scsi-single"

  talos_upload_name = replace(replace(var.talos_image_file_name, ".raw.xz", ".img"), ".xz", ".img")
  boot_disk_gb      = 20
  data_disk_gb      = 1000
}

resource "proxmox_virtual_environment_vm" "control_planes" {
  for_each  = toset(local.control_plane_names)
  node_name = var.pm_node
  name      = each.key
  on_boot   = true
  vm_id = local.vm_ids[each.key]

  cpu {
    sockets = 1
    cores   = 2
    type    = "host"
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.pm_block_store_id
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
  }

  initialization {
    datastore_id = var.pm_block_store_id
    ip_config {
      ipv4 {
        address = "${var.talos_cp_01_ip_addr}/24"
        gateway = var.default_gateway
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "workers" {
  depends_on = [proxmox_virtual_environment_vm.control_planes]
  for_each  = toset(local.worker_names)
  node_name = var.pm_node
  name      = each.key
  on_boot   = true
  vm_id = local.vm_ids[each.key]

  cpu {
    sockets = 1
    cores   = local.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = local.memory_mb
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.pm_block_store_id
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = local.boot_disk_gb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = local.data_disk_gb
    iothread     = true
  }

  initialization {
    datastore_id = var.pm_block_store_id
    ip_config {
      ipv4 {
        address = "${var.talos_worker_01_ip_addr}/24"
        gateway = var.default_gateway
      }
    }
  }
}
