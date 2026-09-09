variable "aws_region" {
  description = "Region AWS donde se desplegara el bastion OpenVPN."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Nombre base para los recursos."
  type        = string
  default     = "BastionOpenVPN"
}

variable "environment" {
  description = "Etiqueta de ambiente."
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "ID de la VPC donde se desplegara el bastion."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC que se publicara a los clientes VPN, ejemplo 10.60.0.0/16."
  type        = string
}

variable "subnet_id" {
  description = "ID de la subnet publica donde se desplegara el bastion."
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Tamano del disco root en GB."
  type        = number
  default     = 20
}

variable "key_name" {
  description = "Nombre del par de llaves en AWS y del archivo .pem local."
  type        = string
  default     = "BastionOpenVPN"
}

variable "ssh_allowed_cidr" {
  description = "CIDR autorizado para SSH. Si es null, Terraform usa tu IP publica actual /32."
  type        = string
  default     = null
}

variable "openvpn_port" {
  description = "Puerto UDP de OpenVPN."
  type        = number
  default     = 1194
}

variable "openvpn_allowed_cidrs" {
  description = "CIDR autorizado para conectarse a OpenVPN."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpn_cidr" {
  description = "CIDR de clientes VPN."
  type        = string
  default     = "10.8.0.0/24"
}

variable "vpn_cidr_network" {
  description = "Network address del pool VPN en formato OpenVPN."
  type        = string
  default     = "10.8.0.0"
}

variable "vpn_cidr_netmask" {
  description = "Netmask del pool VPN en formato OpenVPN."
  type        = string
  default     = "255.255.255.0"
}

variable "initial_client_name" {
  description = "Nombre del primer cliente .ovpn que se genera automaticamente."
  type        = string
  default     = "cliente1"
}

variable "create_eip" {
  description = "Crear y asociar Elastic IP a la instancia."
  type        = bool
  default     = true
}
