# OpenVPN en AWS con Terraform

Plantilla Terraform para desplegar un servidor OpenVPN sobre una instancia EC2 Ubuntu en AWS.

El proyecto permite:

- Crear una instancia EC2 para OpenVPN.
- Crear Security Group.
- Crear Elastic IP opcional.
- Crear Key Pair para acceso SSH.
- Instalar y configurar OpenVPN automáticamente.
- Generar un cliente OpenVPN inicial.
- Crear clientes OpenVPN adicionales.
- Reutilizar la infraestructura para diferentes clientes.

## Estructura del proyecto

```text
terraform-aws-openvpn/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── README.md
├── .gitignore
├── scripts/
│   └── crear-cliente-openvpn.sh
└── docs/
    ├── Manual_OpenVPN_Terraform_GitHub_Mac.pdf
