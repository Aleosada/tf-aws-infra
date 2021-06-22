##########################################################################
# RESOURCES
##########################################################################

resource "aws_vpc" "transit-vpc" {
  cidr_block = var.transit_network_address_space[terraform.workspace]
  tags = {
    Name = "transit-vpc"
  }
}

resource "aws_subnet" "transit-subnet" {
  vpc_id     = aws_vpc.transit-vpc.id
  cidr_block = cidrsubnet(var.transit_network_address_space[terraform.workspace], 8, 0)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "transit-subnet-1"
  }
}

resource "aws_internet_gateway" "transit-igw" {
  vpc_id = aws_vpc.transit-vpc.id

  tags = {
    Name = "transit-igw"
  }
}

resource "aws_route_table" "transit-rtb" {
  vpc_id = aws_vpc.transit-vpc.id

  tags = {
    Name = "transit-rtb"
  }
}

resource "aws_route_table_association" "rta-transit-subnet" {
  subnet_id      = aws_subnet.transit-subnet.id
  route_table_id = aws_route_table.transit-rtb.id
}

resource "aws_route" "route-transit-igw" {
  route_table_id            = aws_route_table.transit-rtb.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.transit-igw.id
}

#resource "aws_security_group" "cisco-router-sg" {
#  name        = "cisco_router_sg"
#  description = "Allows ssh from any source"
#  vpc_id      = aws_vpc.web-vpc.id
#
#  ingress {
#    from_port   = 22
#    to_port     = 22
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = -1
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#}
#
#resource "aws_instance" "cisco-router" {
#  ami                    = data.aws_ami.cisco-router.id
#  instance_type          = "t2.medium"
#  subnet_id              = aws_subnet.transit-subnet.id
#  key_name               = var.key_name
#  security_groups        = [aws_security_group.cisco-router-sg.id]
#
#  tags = {
#    Name = "cisco-router1"
#  }
#}
#
#resource "aws_eip" "cisco-router-eip" {
#  vpc = true
#  instance = aws_instance.cisco-router.id
#  depends_on = [aws_internet_gateway.transit-igw]
#}
