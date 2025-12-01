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

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
    identifier = "ciot-db-${var.environment}"
    
    # Engine Configuration
    engine         = "postgres"
    instance_class = "db.t3.micro"
    
    # Database Configuration
    db_name  = "ciotdb"
    username = local.rds_credentials.username
    password = local.rds_credentials.password
    port     = 5432
    
    # Use manually created secret from setup-secrets.sh
    # Run ./scripts/setup-secrets.sh before terraform apply
    
    # Storage Configuration
    allocated_storage     = 20
    max_allocated_storage = 100
    storage_type          = "gp3"
    storage_encrypted     = true
    
    # Network Configuration
    db_subnet_group_name   = aws_db_subnet_group.main.name
    vpc_security_group_ids = [aws_security_group.rds.id]
    publicly_accessible    = false
    
    # Backup Configuration
    backup_retention_period = 1
    backup_window          = "03:00-04:00"
    maintenance_window     = "mon:04:00-mon:05:00"
    
    # High Availability
    multi_az = false
    
    # Deletion Protection
    deletion_protection = false
    skip_final_snapshot = true
    
    tags = {
        Name        = "ciot-rds-${var.environment}"
        Environment = var.environment
    }
}

# Note: Glue Connection for RDS should be created after RDS instance is set up
# See rds.tf or glue.tf for the connection configuration
# Glue will create ENIs in the private subnets to access RDS via VPC internal routing