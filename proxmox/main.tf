# Proxmox LXC Container for WireGuard Client
resource "proxmox_lxc" "wireguard_client" {
  target_node = var.proxmox_node
  hostname    = "wireguard-client"
  ostemplate  = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged = true
  onboot      = true
  
  # Container resources
  cores  = 1
  memory = 512
  swap   = 512
  
  # Network configuration
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "dhcp"
  }
  
  # Mount points
  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }
  
  # Initial setup script
  start = true
  
  # SSH key for initial access
  ssh_public_keys = var.ssh_public_key
  
  # Connection for provisioning
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.network[0].ip
  }
  
  # Install WireGuard and configure as client
  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y wireguard qrencode",
      "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
      "sysctl -p"
    ]
  }
  
  # WireGuard client config will be managed by Ansible
}

# Output the container's IP for Ansible
output "wireguard_client_ip" {
  value = proxmox_lxc.wireguard_client.network[0].ip
}
