resource "aws_vpc" "k3s" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  region               = "eu-west-3"
  tags = {
    Name = "k3s"
  }
}

resource "aws_subnet" "k3s-private" {
  for_each = {
    "A" = { cidr_block = "10.0.1.0/24", availability_zone = "eu-west-3a" }
    "B" = { cidr_block = "10.0.3.0/24", availability_zone = "eu-west-3b" }
    "C" = { cidr_block = "10.0.5.0/24", availability_zone = "eu-west-3c" }
  }

  vpc_id            = aws_vpc.k3s.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    "Name" = "K3s Private AZ-${each.key}"
    "AZ"   = "${each.key}"
  }
}

resource "aws_subnet" "k3s-public" {
  for_each = {
    "A" = { cidr_block = "10.0.2.0/24", availability_zone = "eu-west-3a" }
    "B" = { cidr_block = "10.0.4.0/24", availability_zone = "eu-west-3b" }
    "C" = { cidr_block = "10.0.6.0/24", availability_zone = "eu-west-3c" }
  }

  vpc_id                  = aws_vpc.k3s.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    "Name" = "K3s Public AZ-${each.key}"
    "AZ"   = "${each.key}"
  }
}



resource "aws_route_table" "k3s-public-rt" {
  vpc_id = aws_vpc.k3s.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k3s-igw.id
  }

  tags = {
    Name = "k3s-public-rt"
  }
}

resource "aws_route_table" "k3s-private-rt" {
  vpc_id = aws_vpc.k3s.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.k3s-nat.id
  }

  tags = {
    Name = "k3s-private-rt"
  }
}

resource "aws_route_table_association" "k3s-rt-association-public" {
  for_each = aws_subnet.k3s-public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.k3s-public-rt.id
}

resource "aws_route_table_association" "k3s-rt-association-private" {
  for_each = aws_subnet.k3s-private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.k3s-private-rt.id
}

resource "aws_internet_gateway" "k3s-igw" {
  vpc_id = aws_vpc.k3s.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "Nat Gateway"
  }
}

resource "aws_nat_gateway" "k3s-nat" {
  availability_mode = "regional"
  connectivity_type = "public"
  vpc_id            = aws_vpc.k3s.id
  allocation_id     = aws_eip.nat.id
}
