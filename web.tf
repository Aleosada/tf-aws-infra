##################################################################################
# CONFIGURATION (for Terraform > 0.12)
##################################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = var.region
}

##########################################################################
# DATA
##########################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "aws-nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##########################################################################
# RESOURCES
##########################################################################

resource "aws_vpc" "web-vpc" {
  cidr_block = var.web_network_address_space[terraform.workspace]
  tags = {
    Name = "web-vpc"
  }
}

resource "aws_subnet" "web-subnet" {
  count      = var.web_subnet_count[terraform.workspace]
  vpc_id     = aws_vpc.web-vpc.id
  cidr_block = cidrsubnet(var.web_network_address_space[terraform.workspace], 8, count.index % var.web_subnet_count[terraform.workspace])
  availability_zone = data.aws_availability_zones.available.names[count.index % var.web_subnet_count[terraform.workspace]]

  tags = {
    Name = "web-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "web-igw" {
  vpc_id = aws_vpc.web-vpc.id

  tags = {
    Name = "web-igw"
  }
}

resource "aws_route_table" "web-rtb" {
  vpc_id = aws_vpc.web-vpc.id

  tags = {
    Name = "web-rtb"
  }
}

resource "aws_route" "web-route-igw" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.web-igw.id
}

resource "aws_route" "route-web-shared" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_cidr_block    = var.shared_network_address_space[terraform.workspace]
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_shared_web.id
}

resource "aws_route_table_association" "rta-subnet" {
  count          = var.web_subnet_count[terraform.workspace]
  subnet_id      = aws_subnet.web-subnet[count.index % var.web_subnet_count[terraform.workspace]].id
  route_table_id = aws_route_table.web-rtb.id
}

resource "aws_security_group" "allow_ssh" {
  name        = "nginx_demo"
  description = "Allow ports for nginx"
  vpc_id      = aws_vpc.web-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "nginx-pub-eip" {
  count = var.nginx_instance_count[terraform.workspace]
  vpc = true
  associate_with_private_ip = cidrhost(aws_subnet.web-subnet[count.index % var.nginx_instance_count[terraform.workspace]].cidr_block, 10)
  depends_on                = [aws_internet_gateway.web-igw]
}

resource "aws_network_interface" "nginx-eth0" {
  count = var.nginx_instance_count[terraform.workspace]
  subnet_id       = aws_subnet.web-subnet[count.index % var.nginx_instance_count[terraform.workspace]].id
  private_ips     = [cidrhost(aws_subnet.web-subnet[count.index % var.web_subnet_count[terraform.workspace]].cidr_block, 10)]
  security_groups = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "nginx-eth-${count.index}"
  }
}

resource "aws_eip_association" "eip_assoc" {
  count = var.nginx_instance_count[terraform.workspace]
  network_interface_id = aws_network_interface.nginx-eth0[count.index % var.nginx_instance_count[terraform.workspace]].id
  allocation_id = aws_eip.nginx-pub-eip[count.index % var.nginx_instance_count[terraform.workspace]].id
}

resource "aws_instance" "nginx" {
  count                  = var.nginx_instance_count[terraform.workspace]
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.nginx_instance_size[terraform.workspace]
  key_name               = var.key_name

  network_interface {
    network_interface_id = aws_network_interface.nginx-eth0[count.index % var.nginx_instance_count[terraform.workspace]].id
    device_index         = 0
  }

  connection {
    type        = "ssh"
    host        = aws_eip.nginx-pub-eip[count.index % var.nginx_instance_count[terraform.workspace]].public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start",
      "sudo pip install s3cmd",
    ]
  }

  tags = {
    Name = "nginx-${count.index}"
  }
}
