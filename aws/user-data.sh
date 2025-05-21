#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    wireguard \
    qrencode \
    iptables-persistent \
    fail2ban \
    unattended-upgrades \
    ufw \
    nginx \
    certbot \
    python3-certbot-nginx

# Configure automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOL
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOL

# Configure UFW (Uncomplicated Firewall)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH, HTTP, HTTPS, and WireGuard
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 51820/udp comment 'WireGuard'
ufw --force enable

# Configure SSH security
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
echo "AllowUsers ubuntu" >> /etc/ssh/sshd_config

# Configure fail2ban
cat > /etc/fail2ban/jail.local <<EOL
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
ignoreip = 127.0.0.1/8 ::1
EOL

# Enable IP forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf
sysctl -p

# Generate WireGuard server keys
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Create WireGuard server config
cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private.key)
Address = 10.10.10.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Client configuration will be added here by Ansible
EOL

# Create client config directory
mkdir -p /etc/wireguard/clients

# Enable and start services
systemctl restart sshd
systemctl enable fail2ban
systemctl start fail2ban
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Configure Nginx as reverse proxy
cat > /etc/nginx/sites-available/default <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    # Default catch-all - return 404
    location / {
        return 404;
    }
}

# Example public-facing service (replace with your domain)
# server {
#     listen 80;
#     server_name app.yourdomain.com;
#     
#     location / {
#         proxy_pass http://10.10.10.2:3000;  # Your React app
#         proxy_http_version 1.1;
#         proxy_set_header Upgrade \$http_upgrade;
#         proxy_set_header Connection 'upgrade';
#         proxy_set_header Host \$host;
#         proxy_cache_bypass \$http_upgrade;
#     }
# }

# Example private service (only accessible via WireGuard)
# server {
#     listen 80;
#     server_name internal.yourdomain.com;
#     
#     # Only allow from WireGuard network
#     allow 10.10.10.0/24;
#     deny all;
#     
#     location / {
#         proxy_pass http://10.10.10.2:32400;  # Plex example
#         proxy_http_version 1.1;
#         proxy_set_header Host \$host;
#     }
# }
EOL

# Enable Nginx
systemctl enable nginx
systemctl restart nginx

# Print initial WireGuard client config
echo "WireGuard Server Public Key:"
cat /etc/wireguard/server_public.key
echo -e "\nAdd this to your client config:"
echo "[Peer]"
echo "PublicKey = $(cat /etc/wireguard/server_public.key)"
echo "AllowedIPs = 10.10.10.0/24"
echo "Endpoint = $(curl -s ifconfig.me):51820"
echo "PersistentKeepalive = 25"

echo -e "\n\nNext steps:"
echo "1. Set up your DNS records to point to $(curl -s ifconfig.me)"
echo "2. Uncomment and edit the Nginx server blocks in /etc/nginx/sites-available/default"
echo "3. Run 'sudo certbot --nginx' to set up HTTPS"
echo "4. Restart Nginx: 'sudo systemctl restart nginx'"
