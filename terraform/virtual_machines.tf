locals {
  cidata_map = { for name, _ in var.nodes : name => "local:iso/${name}-cidata.iso" }
}

resource "proxmox_vm_qemu" "talos_nodes" {
  for_each    = var.nodes
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

  network {
    model  = "virtio"
    bridge = var.bridge
  }

  disk {
    type    = "scsi"
    storage = var.vm_storage
    size    = each.value.os_disk
  }

  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      type     = "scsi"
      storage  = var.vm_storage
      size     = disk.value
      iothread = 1
      ssd      = 1
    }
  }
}

resource "null_resource" "attach_cidata" {
  for_each   = var.nodes
  depends_on = [proxmox_vm_qemu.talos_nodes]

  triggers = {
    vmid     = proxmox_vm_qemu.talos_nodes[each.key].vmid
    cidata   = local.cidata_map[each.key]          # e.g., local:iso/w1-cidata.iso
  }

  provisioner "remote-exec" {
    inline = [
      # attach as IDE2 cdrom
      "qm set ${self.triggers.vmid} -ide2 ${self.triggers.cidata},media=cdrom"
    ]

    connection {
      host = var.pm_ssh_host   # e.g. "root@REDACTED_IP"
      # your ssh private key/user already configured in the workflow
    }
  }
}
