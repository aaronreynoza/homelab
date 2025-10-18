resource "proxmox_vm_qemu" "talos_nodes" {
  for_each = var.nodes

  depends_on = [null_resource.talos_template]

  name        = each.key
  target_node = var.pm_node
  clone       = var.template_name
  full_clone  = true

  agent   = 0
  sockets = 1
  cores   = each.value.cores
  memory  = each.value.memory
  onboot  = true

  scsihw  = "virtio-scsi-single"
  boot    = "order=scsi0"

  # Require a per-node cidata ISO path (e.g., local:iso/w1-cidata.iso)
  # var.config_isos must contain an entry for each node name
  ide2 = "${var.config_isos[each.key]},media=cdrom"

  network {
    model  = "virtio"
    bridge = var.bridge
  }

  # Grow OS disk beyond template size if desired
  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = each.value.os_disk
  }

  # Optional data disk (only if not null)
  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      type     = "scsi"
      storage  = var.vm_storage
      size     = disk.value
      iothread = true
      ssd      = true
    }
  }
}
