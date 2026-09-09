<<<<<<< HEAD
# terraform-aws-openvpn
Plantilla Terraform para desplegar un servidor o bastion openvpn en AWS
=======
# Bastion OpenVPN en Ubuntu 26.04 LTS con Terraform

## Uso

1. Copia el ejemplo de variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edita `terraform.tfvars` con `vpc_id`, `vpc_cidr`, `subnet_id` y region.

3. Ejecuta:

```bash
terraform init
terraform plan
terraform apply
```

4. Al terminar, Terraform crea el archivo `BastionOpenVPN.pem` localmente con permisos `0400`.

5. Para entrar por SSH:

```bash
terraform output ssh_command
```

6. Para descargar el perfil inicial:

```bash
terraform output download_client_ovpn_command
```

7. Logs de instalacion en la instancia:

```bash
sudo tail -f /var/log/openvpn-bootstrap.log
sudo systemctl status openvpn-server@server
```

## Notas

- El servidor usa `/etc/openvpn/server/server.conf`.
- El servicio es `openvpn-server@server`.
- El perfil inicial queda en `~/client-configs/files/cliente1.ovpn`.
- La VPN usa NAT con nftables para simplificar conectividad hacia la VPC.


## Ubuntu 26.04 LTS

Esta plantilla usa la AMI oficial de Canonical desde SSM Parameter Store:

```text
/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id
```

Para instancias x86_64 actuales como `t3.micro`, `t3.small`, `t3.medium`, `t4g` no aplica porque `t4g` es ARM64. Si se usa ARM64, hay que cambiar `amd64` por `arm64` y escoger una instancia Graviton, por ejemplo `t4g.micro`.
>>>>>>> 39d0b5a (feat: plantilla inicial OpenVPN con Terraform)
