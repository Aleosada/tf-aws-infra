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
  assign_generated_ipv6_cidr_block = true
  tags = merge({ Name = "web-vpc" }, local.common_tags)
}

resource "aws_iam_role" "flowlogs-role" {
  name = "flowlogs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "flowlogs-role-policy" {
  name = "flowlogs-role-policy"
  role = aws_iam_role.flowlogs-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "flowlog" {
  name = "flowlog"
  tags = local.common_tags
}

resource "aws_flow_log" "web-vpc-flowlogs-accepted" {
  iam_role_arn    = aws_iam_role.flowlogs-role.arn
  log_destination = aws_cloudwatch_log_group.flowlog.arn
  traffic_type    = "ACCEPT"
  vpc_id          = aws_vpc.web-vpc.id
  tags = local.common_tags
}

resource "aws_flow_log" "web-vpc-flowlogs-rejected" {
  iam_role_arn    = aws_iam_role.flowlogs-role.arn
  log_destination = aws_cloudwatch_log_group.flowlog.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.web-vpc.id
  tags = local.common_tags
}

resource "aws_subnet" "web-subnet" {
  count      = var.web_subnet_count[terraform.workspace]
  vpc_id     = aws_vpc.web-vpc.id
  cidr_block = cidrsubnet(var.web_network_address_space[terraform.workspace], 8, count.index % var.web_subnet_count[terraform.workspace])
  ipv6_cidr_block = cidrsubnet(aws_vpc.web-vpc.ipv6_cidr_block, 8, count.index % var.web_subnet_count[terraform.workspace])
  availability_zone = data.aws_availability_zones.available.names[count.index % var.web_subnet_count[terraform.workspace]]

  tags = merge({ Name = "web-subnet-${count.index}" }, local.common_tags)
}

resource "aws_internet_gateway" "web-igw" {
  vpc_id = aws_vpc.web-vpc.id

  tags = merge({ Name = "web-igw" }, local.common_tags)
}

resource "aws_route_table" "web-rtb" {
  vpc_id = aws_vpc.web-vpc.id

  tags = merge({ Name = "web-rtb" }, local.common_tags)
}

resource "aws_route" "web-route-igw" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.web-igw.id
}

resource "aws_route" "web-route-igw-ipv6" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_ipv6_cidr_block = "::/0"
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
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = local.common_tags
}

resource "aws_eip" "nginx-pub-eip" {
  count = var.nginx_instance_count[terraform.workspace]
  vpc = true
  associate_with_private_ip = cidrhost(aws_subnet.web-subnet[count.index % var.nginx_instance_count[terraform.workspace]].cidr_block, 10)
  depends_on                = [aws_internet_gateway.web-igw]
  tags = local.common_tags
}

resource "aws_network_interface" "nginx-eth0" {
  count = var.nginx_instance_count[terraform.workspace]
  subnet_id       = aws_subnet.web-subnet[count.index % var.nginx_instance_count[terraform.workspace]].id
  private_ips     = [cidrhost(aws_subnet.web-subnet[count.index % var.web_subnet_count[terraform.workspace]].cidr_block, 10)]
  ipv6_address_count = 1
  security_groups = [aws_security_group.allow_ssh.id]

  tags = merge({ Name = "nginx-eth-${count.index}" }, local.common_tags)
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

  tags = merge({ Name = "nginx-${count.index}" }, local.common_tags)
}
