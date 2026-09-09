output "instance_id" {
  value = aws_instance.openvpn.id
}

output "public_ip" {
  value = var.create_eip ? aws_eip.openvpn[0].public_ip : aws_instance.openvpn.public_ip
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${var.create_eip ? aws_eip.openvpn[0].public_ip : aws_instance.openvpn.public_ip}"
}

output "download_client_ovpn_command" {
  value = "scp -i ${var.key_name}.pem ubuntu@${var.create_eip ? aws_eip.openvpn[0].public_ip : aws_instance.openvpn.public_ip}:~/client-configs/files/${var.initial_client_name}.ovpn ."
}

output "private_key_file" {
  value     = local.key_filename
  sensitive = true
}
