##########################################################################
# RESOURCES
##########################################################################

resource "aws_vpc" "shared-vpc" {
  cidr_block = var.shared_network_address_space[terraform.workspace]
  tags = {
    Name = "shared-vpc"
  }
}

resource "aws_subnet" "shared-priv-subnet" {
  count      = var.shared_priv_subnet_count[terraform.workspace]
  vpc_id     = aws_vpc.shared-vpc.id
  cidr_block = cidrsubnet(var.shared_network_address_space[terraform.workspace], 8, count.index % var.shared_priv_subnet_count[terraform.workspace])
  availability_zone = data.aws_availability_zones.available.names[count.index % var.shared_priv_subnet_count[terraform.workspace]]

  tags = {
    Name = "shared-priv-subnet-${count.index}"
  }
}

resource "aws_subnet" "shared-pub-subnet" {
  count      = var.shared_pub_subnet_count[terraform.workspace]
  vpc_id     = aws_vpc.shared-vpc.id
  cidr_block = cidrsubnet(var.shared_network_address_space[terraform.workspace], 8, (count.index % var.shared_pub_subnet_count[terraform.workspace]) + var.shared_priv_subnet_count[terraform.workspace])
  availability_zone = data.aws_availability_zones.available.names[count.index % var.shared_pub_subnet_count[terraform.workspace]]

  tags = {
    Name = "shared-pub-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "shared-igw" {
  vpc_id = aws_vpc.shared-vpc.id

  tags = {
    Name = "shared-igw"
  }
}

resource "aws_route_table" "shared-priv-rtb" {
  vpc_id = aws_vpc.shared-vpc.id

  tags = {
    Name = "shared-priv-rtb"
  }
}

resource "aws_route_table_association" "rta-priv-subnet" {
  count          = var.shared_priv_subnet_count[terraform.workspace]
  subnet_id      = aws_subnet.shared-priv-subnet[count.index % var.shared_priv_subnet_count[terraform.workspace]].id
  route_table_id = aws_route_table.shared-priv-rtb.id
}

resource "aws_route_table" "shared-pub-rtb" {
  vpc_id = aws_vpc.shared-vpc.id

  tags = {
    Name = "shared-pub-rtb"
  }
}

resource "aws_route_table_association" "rta-pub-subnet" {
  count          = var.shared_pub_subnet_count[terraform.workspace]
  subnet_id      = aws_subnet.shared-pub-subnet[count.index % var.shared_pub_subnet_count[terraform.workspace]].id
  route_table_id = aws_route_table.shared-pub-rtb.id
}

resource "aws_route" "route-shared-pub-igw" {
  route_table_id            = aws_route_table.shared-pub-rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.shared-igw.id
}

resource "aws_vpc_peering_connection" "vpc_peering_shared_web" {
  peer_vpc_id   = aws_vpc.web-vpc.id
  vpc_id        = aws_vpc.shared-vpc.id
  auto_accept   = true

  tags = {
    Name = "VPC Peering between shared and web"
  }
}

resource "aws_route" "route-shared-priv-web" {
  route_table_id            = aws_route_table.shared-priv-rtb.id
  destination_cidr_block    = var.web_network_address_space[terraform.workspace]
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_shared_web.id
}

resource "aws_security_group" "database-sg" {
  name        = "database-sg"
  description = "Allows database connections"
  vpc_id      = aws_vpc.shared-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16", var.web_network_address_space[terraform.workspace], var.shared_network_address_space[terraform.workspace]]
  }
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.web_network_address_space[terraform.workspace]]
  }
  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["192.168.0.0/16", var.web_network_address_space[terraform.workspace], var.shared_network_address_space[terraform.workspace]]
  }
}

resource "aws_security_group" "nat-sg" {
  name        = "nat-sg"
  description = "Allows ssh an traffic from shared vpc"
  vpc_id      = aws_vpc.shared-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "all"
    cidr_blocks = ["10.0.0.0/8","192.168.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "db" {
  count                  = var.db_instance_count[terraform.workspace]
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.db_instance_size[terraform.workspace]
  key_name               = var.key_name
  subnet_id              = aws_subnet.shared-priv-subnet[count.index % var.db_instance_count[terraform.workspace]].id
  security_groups        = [aws_security_group.database-sg.id]

  tags = {
    Name = "db${count.index+1}"
  }
}

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.aws-nat.id
  instance_type          = var.nat_instance_size[terraform.workspace]
  subnet_id              = aws_subnet.shared-pub-subnet[0].id
  source_dest_check      = false
  key_name               = var.key_name
  security_groups        = [aws_security_group.nat-sg.id]

  tags = {
    Name = "nat1"
  }
}

resource "aws_eip" "nat-eip" {
  vpc = true
  instance = aws_instance.nat.id
  depends_on = [aws_internet_gateway.shared-igw]
}

resource "aws_route" "route-shared-priv-nat" {
  route_table_id            = aws_route_table.shared-priv-rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  instance_id               = aws_instance.nat.id
}
