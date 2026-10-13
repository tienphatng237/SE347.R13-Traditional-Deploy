output "public_ip" {
  description = "Public IP address of the web server."
  value       = aws_instance.web.public_ip
}
output "public_dns" {
  description = "Public DNS name of the web server."
  value       = aws_instance.web.public_dns
}
output "ssh_command" {
  description = "Replace PATH_TO_KEY with the path to your private key."
  value       = "ssh -i PATH_TO_KEY ubuntu@${aws_instance.web.public_ip}"
}
