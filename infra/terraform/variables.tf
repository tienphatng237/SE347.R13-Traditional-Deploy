variable "aws_region" {
  description = "AWS region in which to create the server."
  type        = string
  default     = "ap-southeast-1"
}
variable "project_name" {
  description = "Prefix used to name AWS resources."
  type        = string
  default     = "roadmap-maker"
}
variable "key_name" {
  description = "Tên key pair sẽ được Terraform tạo trên AWS từ public key cục bộ trong key_pair/."
  type        = string
  default     = "roadmap-maker-key"
}
variable "ssh_allowed_cidr" {
  description = "Your public IP in CIDR notation, for example 203.0.113.10/32. Never use 0.0.0.0/0."
  type        = string
}
variable "instance_type" {
  description = "EC2 instance size. t3.micro is enough for a small course demonstration."
  type        = string
  default     = "t3.micro"
}
variable "vpc_cidr" {
  description = "CIDR range for the dedicated VPC."
  type        = string
  default     = "10.20.0.0/16"
}
variable "public_subnet_cidr" {
  description = "CIDR range for the public subnet hosting the EC2 instance."
  type        = string
  default     = "10.20.10.0/24"
}
