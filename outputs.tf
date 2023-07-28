output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.app_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  # public_ipはmain.tfのapp_serverにはないが、terraform apply時に出てくるので使える
  value = aws_instance.app_server.public_ip
}