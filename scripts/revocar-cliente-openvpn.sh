#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: no ejecute este script con sudo."
  echo "Ejecutelo como usuario ubuntu:"
  echo "~/revocar-cliente-openvpn.sh nombre_cliente"
  exit 1
fi

EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_DIR="/etc/openvpn/server"
SERVER_CONF="${SERVER_DIR}/server.conf"
OUTPUT_DIR="/home/ubuntu/client-configs/files"
SERVICE="openvpn-server@server"

# Vigencia de la CRL en dias. Si la CRL vence, OpenVPN rechaza a TODOS los clientes.
CRL_DAYS=3650

usage() {
  echo "Uso:"
  echo "  $0 nombre_cliente              Revoca el cliente (la sesion activa cae al reconectar o renegociar, max. 1 hora)"
  echo "  $0 nombre_cliente --reiniciar  Revoca y reinicia OpenVPN para desconectarlo ya (desconecta a todos unos segundos)"
  echo "  $0 --listar                    Lista clientes vigentes (V) y revocados (R)"
  echo "Ejemplo: $0 carlos.rojas"
}

listar() {
  echo "Estado  Vence         Cliente"
  sudo awk -F'\t' '$6 != "/CN=server" {
    cn = $6; sub(/^.*CN=/, "", cn)
    printf "%-7s %s/%s/%s  %s\n", $1, "20" substr($2,1,2), substr($2,3,2), substr($2,5,2), cn
  }' "$EASYRSA_DIR/pki/index.txt"
}

# Genera la CRL, la publica para OpenVPN y habilita crl-verify si aun no lo esta.
publicar_crl() {
  sudo bash -c "cd '$EASYRSA_DIR' && EASYRSA_CRL_DAYS=$CRL_DAYS ./easyrsa --batch gen-crl"
  sudo install -m 644 -o root -g root "$EASYRSA_DIR/pki/crl.pem" "$SERVER_DIR/crl.pem"

  if ! sudo grep -q '^crl-verify' "$SERVER_CONF"; then
    echo "Habilitando crl-verify en $SERVER_CONF (requiere reiniciar OpenVPN una unica vez)..."
    echo "crl-verify crl.pem" | sudo tee -a "$SERVER_CONF" > /dev/null
    REINICIAR=1
  fi
}

CLIENT_NAME="${1:-}"
REINICIAR=0

if [ "$CLIENT_NAME" = "--listar" ]; then
  listar
  exit 0
fi

if [ -z "$CLIENT_NAME" ]; then
  usage
  exit 1
fi

if [ "${2:-}" = "--reiniciar" ]; then
  REINICIAR=1
elif [ -n "${2:-}" ]; then
  usage
  exit 1
fi

if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: el nombre del cliente solo puede contener letras, numeros, punto, guion y guion bajo."
  exit 1
fi

if [ "$CLIENT_NAME" = "server" ]; then
  echo "Error: no se puede revocar el certificado del servidor."
  exit 1
fi

if ! sudo test -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt"; then
  echo "Error: no existe un certificado vigente para '$CLIENT_NAME'."
  echo "Clientes registrados:"
  listar
  exit 1
fi

echo "Revocando certificado de: $CLIENT_NAME"
sudo bash -c "cd '$EASYRSA_DIR' && ./easyrsa --batch revoke '$CLIENT_NAME'"

echo "Generando y publicando CRL..."
publicar_crl

if [ -f "$OUTPUT_DIR/${CLIENT_NAME}.ovpn" ]; then
  rm -f "$OUTPUT_DIR/${CLIENT_NAME}.ovpn"
  echo "Perfil eliminado: $OUTPUT_DIR/${CLIENT_NAME}.ovpn"
fi

if [ "$REINICIAR" -eq 1 ]; then
  echo "Reiniciando $SERVICE..."
  sudo systemctl restart "$SERVICE"
  sleep 2
  if ! sudo systemctl is-active --quiet "$SERVICE"; then
    echo "Error: $SERVICE no levanto. Revise: sudo journalctl -u $SERVICE -n 50"
    exit 1
  fi
fi

echo ""
echo "Cliente '$CLIENT_NAME' revocado correctamente."
echo "Su .ovpn ya no puede establecer nuevas conexiones."
if [ "$REINICIAR" -eq 0 ]; then
  echo "Si tenia una sesion activa, se cortara al reconectar o en la siguiente renegociacion (max. 1 hora)."
  echo "Para cortarla ya: $0 $CLIENT_NAME --reiniciar"
fi
