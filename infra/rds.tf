# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "ciot-rds-sg-${var.environment}"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from VPC"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ciot-rds-sg-${var.environment}"
  }
}

# DB Subnet Group (required for RDS)
resource "aws_db_subnet_group" "main" {
  name       = "ciot-db-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "ciot-db-subnet-group-${var.environment}"
  }
}

# Note: Glue Connection for RDS should be created after RDS instance is set up
# See rds.tf or glue.tf for the connection configuration
# Glue will create ENIs in the private subnets to access RDS via VPC internal routing