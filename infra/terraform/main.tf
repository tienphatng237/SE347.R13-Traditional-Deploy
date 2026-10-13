provider "aws" {
  region = var.aws_region
}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Stack     = "traditional-web-deployment"
  }
}
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-igw" })
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-subnet" })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-rt" })
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web"
  description = "Allow public web traffic and SSH only from the administrator."
  vpc_id      = aws_vpc.this.id
  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH from the administrator only"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-web-sg" })
}
resource "aws_key_pair" "web" {
  key_name   = var.key_name
  public_key = file("${path.module}/../../key_pair/${var.key_name}.pub")
  tags       = merge(local.common_tags, { Name = var.key_name })
}
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = aws_key_pair.web.key_name
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/templates/cloud-init.sh.tftpl", {})
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted   = true
    volume_size = 20
    volume_type = "gp3"
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-web" })
}
