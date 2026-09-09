#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: no ejecute este script con sudo."
  echo "Ejecutelo como usuario ubuntu:"
  echo "~/crear-cliente-openvpn.sh nombre_cliente"
  exit 1
fi

CLIENT_NAME="${1:-}"

if [ -z "$CLIENT_NAME" ]; then
  echo "Uso: $0 nombre_cliente"
  echo "Ejemplo: $0 carlos.rojas"
  exit 1
fi

if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: el nombre del cliente solo puede contener letras, numeros, punto, guion y guion bajo."
  exit 1
fi

EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_DIR="/etc/openvpn/server"
OUTPUT_DIR="/home/ubuntu/client-configs/files"
CLIENT_FILE="${OUTPUT_DIR}/${CLIENT_NAME}.ovpn"

TOKEN="$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"

if [ -n "$TOKEN" ]; then
  PUBLIC_IP="$(curl -s \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 || true)"

  PUBLIC_DNS="$(curl -s \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-hostname || true)"
else
  PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  PUBLIC_DNS="$(curl -s http://169.254.169.254/latest/meta-data/public-hostname || true)"
fi

REMOTE_HOST="${PUBLIC_DNS:-$PUBLIC_IP}"

if [ -z "$REMOTE_HOST" ]; then
  echo "Error: no se pudo obtener IP publica ni DNS publico desde AWS Metadata."
  echo "Valide que la instancia tenga IP publica o Elastic IP asociada."
  exit 1
fi

if ! sudo test -d "$EASYRSA_DIR"; then
  echo "Error: no existe $EASYRSA_DIR"
  exit 1
fi

if ! sudo test -f "$SERVER_DIR/ca.crt"; then
  echo "Error: no existe $SERVER_DIR/ca.crt"
  exit 1
fi

if ! sudo test -f "$SERVER_DIR/tls-crypt.key"; then
  echo "Error: no existe $SERVER_DIR/tls-crypt.key"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
chmod 700 /home/ubuntu/client-configs
chmod 700 "$OUTPUT_DIR"

if sudo test -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" && sudo test -f "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key"; then
  echo "El certificado y la llave del cliente ya existen."
  echo "Se regenerara solo el archivo .ovpn."
else
  echo "Creando solicitud de certificado para: $CLIENT_NAME"
  sudo bash -c "cd '$EASYRSA_DIR' && ./easyrsa gen-req '$CLIENT_NAME' nopass"

  echo "Firmando certificado como cliente..."
  sudo bash -c "cd '$EASYRSA_DIR' && ./easyrsa --batch sign-req client '$CLIENT_NAME'"
fi

if ! sudo test -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt"; then
  echo "Error: no se encontro el certificado firmado del cliente."
  exit 1
fi

if ! sudo test -f "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key"; then
  echo "Error: no se encontro la llave privada del cliente."
  exit 1
fi

echo "Generando archivo: $CLIENT_FILE"

cat > "$CLIENT_FILE" <<EOF
client
dev tun
proto udp
remote ${REMOTE_HOST} 1194
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
EOF

sudo cat "$SERVER_DIR/ca.crt" >> "$CLIENT_FILE"

cat >> "$CLIENT_FILE" <<EOF
</ca>
<cert>
EOF

sudo sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" >> "$CLIENT_FILE"

cat >> "$CLIENT_FILE" <<EOF
</cert>
<key>
EOF

sudo cat "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key" >> "$CLIENT_FILE"

cat >> "$CLIENT_FILE" <<EOF
</key>
<tls-crypt>
EOF

sudo cat "$SERVER_DIR/tls-crypt.key" >> "$CLIENT_FILE"

cat >> "$CLIENT_FILE" <<EOF
</tls-crypt>
EOF

chmod 600 "$CLIENT_FILE"
sudo chown ubuntu:ubuntu "$CLIENT_FILE"

echo ""
echo "Cliente OpenVPN creado correctamente."
echo "Archivo generado:"
echo "$CLIENT_FILE"
echo ""
echo "Servidor remoto usado en el perfil:"
echo "$REMOTE_HOST"
echo ""
echo "Para descargarlo desde su equipo local:"
echo "scp -i BastionOpenVPN.pem ubuntu@${REMOTE_HOST}:~/client-configs/files/${CLIENT_NAME}.ovpn ."