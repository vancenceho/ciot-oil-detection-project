# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ciot-vpc-${var.environment}"
  }
}

# Private Subnets (for RDS)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ciot-private-subnet-${var.environment}-${count.index + 1}"
  }
}

# Route Table for Private Subnets (local VPC routing only, no internet)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Default local route for VPC CIDR is automatically added
  # No internet gateway or NAT gateway needed

  tags = {
    Name = "ciot-private-rt-${var.environment}"
  }
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
