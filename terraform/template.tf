resource "null_resource" "talos_template" {
  triggers = {
    talos_image_url = var.talos_image_url
    template_vmid   = var.template_vmid
    template_name   = var.template_name
    vm_storage      = var.vm_storage
    pm_node         = var.pm_node
    bridge          = var.bridge
  }

  # Requires passwordless SSH or SSH key to the Proxmox node
provisioner "local-exec" {
  command = <<EOT
set -euo pipefail
SSH="${var.pm_ssh_host}"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

ISO_DIR="/var/lib/vz/template/iso"
IMG_XZ="$ISO_DIR/talos.raw.xz"
IMG_RAW="$ISO_DIR/talos.raw"

# 1) fetch Talos
ssh $SSH_OPTS "$SSH" "mkdir -p $ISO_DIR && rm -f $IMG_XZ && curl -L '${var.talos_image_url}' -o '$IMG_XZ'"
ssh $SSH_OPTS "$SSH" "xz -T0 -f -d '$IMG_XZ' || true"

# 2) recreate thin template shell
ssh $SSH_OPTS "$SSH" "qm stop ${var.template_vmid} >/dev/null 2>&1 || true"
ssh $SSH_OPTS "$SSH" "qm destroy ${var.template_vmid} --purge >/dev/null 2>&1 || true"
ssh $SSH_OPTS "$SSH" "qm create ${var.template_vmid} --name ${var.template_name} \
  --memory 2048 --cores 2 --sockets 1 --agent 0 --ostype l26 \
  --net0 virtio,bridge=${var.bridge} --scsihw virtio-scsi-single \
  --serial0 socket --vga serial0"

# 3) import disk and template
ssh $SSH_OPTS "$SSH" "qm importdisk ${var.template_vmid} '$IMG_RAW' ${var.vm_storage} --format raw"
ssh $SSH_OPTS "$SSH" "qm set ${var.template_vmid} --scsi0 ${var.vm_storage}:vm-${var.template_vmid}-disk-0"
ssh $SSH_OPTS "$SSH" "qm set ${var.template_vmid} --boot order=scsi0"
ssh $SSH_OPTS "$SSH" "qm template ${var.template_vmid}"
EOT
}
}
