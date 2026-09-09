terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Detecta tu IP publica actual para limitar SSH.
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

# AMI oficial Canonical Ubuntu Server 26.04 LTS Resolute amd64, gp3.
# Canonical publica AMIs oficiales en SSM Parameter Store bajo /aws/service/canonical.
data "aws_ssm_parameter" "ubuntu_2604" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  ssh_cidr     = var.ssh_allowed_cidr == null ? "${chomp(data.http.my_public_ip.response_body)}/32" : var.ssh_allowed_cidr
  vpc_network  = cidrhost(var.vpc_cidr, 0)
  vpc_netmask  = cidrnetmask(var.vpc_cidr)
  key_filename = "${path.module}/${var.key_name}.pem"
}

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = var.key_name
  public_key = tls_private_key.bastion.public_key_openssh

  tags = {
    Name        = var.key_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "local_sensitive_file" "bastion_pem" {
  filename        = local.key_filename
  content         = tls_private_key.bastion.private_key_pem
  file_permission = "0400"
}

resource "aws_security_group" "openvpn" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for OpenVPN bastion"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from operator public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.ssh_cidr]
  }

  ingress {
    description = "OpenVPN UDP"
    from_port   = var.openvpn_port
    to_port     = var.openvpn_port
    protocol    = "udp"
    cidr_blocks = var.openvpn_allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name_prefix}-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_instance" "openvpn" {
  ami                         = data.aws_ssm_parameter.ubuntu_2604.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.openvpn.id]
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data_replace_on_change = true

  user_data = <<-CLOUDINIT
#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/openvpn-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

apt-get update
apt-get upgrade -y
apt-get install -y openvpn easy-rsa nftables curl ca-certificates

mkdir -p /etc/openvpn/server /var/log/openvpn /home/ubuntu/client-configs/files
chown -R ubuntu:ubuntu /home/ubuntu/client-configs
chmod 700 /home/ubuntu/client-configs

# PKI OpenVPN
if [ ! -d /etc/openvpn/easy-rsa ]; then
  make-cadir /etc/openvpn/easy-rsa
fi

cd /etc/openvpn/easy-rsa
./easyrsa init-pki
EASYRSA_BATCH=1 EASYRSA_REQ_CN="${var.name_prefix}-CA" ./easyrsa build-ca nopass
EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
EASYRSA_BATCH=1 ./easyrsa sign-req server server
./easyrsa gen-dh

# Cliente inicial
EASYRSA_BATCH=1 ./easyrsa gen-req ${var.initial_client_name} nopass
EASYRSA_BATCH=1 ./easyrsa sign-req client ${var.initial_client_name}

cp pki/ca.crt /etc/openvpn/server/ca.crt
cp pki/issued/server.crt /etc/openvpn/server/server.crt
cp pki/private/server.key /etc/openvpn/server/server.key
cp pki/dh.pem /etc/openvpn/server/dh.pem
openvpn --genkey secret /etc/openvpn/server/tls-crypt.key
chmod 600 /etc/openvpn/server/server.key /etc/openvpn/server/tls-crypt.key

cat > /etc/openvpn/server/server.conf <<'OVPN_SERVER_CONF'
port ${var.openvpn_port}
proto udp
dev tun

ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt tls-crypt.key

server ${var.vpn_cidr_network} ${var.vpn_cidr_netmask}
topology subnet
ifconfig-pool-persist ipp.txt

# Ruta hacia la VPC. No redirige todo internet por la VPN.
push "route ${local.vpc_network} ${local.vpc_netmask}"

keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup

auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM

status /var/log/openvpn/status.log
verb 3
explicit-exit-notify 1
OVPN_SERVER_CONF

# IP forwarding
cat > /etc/sysctl.d/99-openvpn.conf <<'SYSCTL_CONF'
net.ipv4.ip_forward=1
SYSCTL_CONF
sysctl --system

# NAT optimizado con nftables: los servidores privados ven el trafico desde la IP privada del bastion.
IFACE=$(ip route | awk '/default/ {print $5; exit}')
cat > /etc/nftables.conf <<NFT_CONF
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    ip saddr ${var.vpn_cidr} oifname "$IFACE" masquerade
  }
}

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy accept;
  }
  chain forward {
    type filter hook forward priority 0;
    policy accept;
  }
  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
NFT_CONF

systemctl enable nftables
systemctl restart nftables
systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

# Perfil .ovpn del cliente inicial
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
CLIENT_OVPN="/home/ubuntu/client-configs/files/${var.initial_client_name}.ovpn"

cat > "$CLIENT_OVPN" <<CLIENT_CONF
client
dev tun
proto udp
remote $PUBLIC_IP ${var.openvpn_port}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
verb 3
key-direction 1

<ca>
CLIENT_CONF
cat /etc/openvpn/server/ca.crt >> "$CLIENT_OVPN"
cat >> "$CLIENT_OVPN" <<CLIENT_CONF
</ca>
<cert>
CLIENT_CONF
sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "/etc/openvpn/easy-rsa/pki/issued/${var.initial_client_name}.crt" >> "$CLIENT_OVPN"
cat >> "$CLIENT_OVPN" <<CLIENT_CONF
</cert>
<key>
CLIENT_CONF
cat "/etc/openvpn/easy-rsa/pki/private/${var.initial_client_name}.key" >> "$CLIENT_OVPN"
cat >> "$CLIENT_OVPN" <<CLIENT_CONF
</key>
<tls-crypt>
CLIENT_CONF
cat /etc/openvpn/server/tls-crypt.key >> "$CLIENT_OVPN"
cat >> "$CLIENT_OVPN" <<CLIENT_CONF
</tls-crypt>
CLIENT_CONF

chown -R ubuntu:ubuntu /home/ubuntu/client-configs
chmod 600 "$CLIENT_OVPN"

systemctl status openvpn-server@server --no-pager
CLOUDINIT

  tags = {
    Name        = var.name_prefix
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [local_sensitive_file.bastion_pem]
}

resource "aws_eip" "openvpn" {
  count    = var.create_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.openvpn.id

  tags = {
    Name        = "${var.name_prefix}-eip"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
