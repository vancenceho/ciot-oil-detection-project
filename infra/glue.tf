# Security Group for Glue ENIs
# Note: Glue requires all ingress and egress ports to be open (can be restricted to same security group)
resource "aws_security_group" "glue" {
  name        = "ciot-glue-sg-${var.environment}"
  description = "Security group for Glue ENIs to access RDS, S3, and AWS services"
  vpc_id      = aws_vpc.main.id

  # Glue requirement: All ingress ports open (restricted to same security group for security)
  ingress {
    description     = "All ingress ports from same security group (Glue requirement)"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  # Glue requirement: All egress ports open (restricted to same security group for security)
  egress {
    description     = "All egress ports to same security group (Glue requirement)"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  # HTTPS to S3 and AWS services
  egress {
    description = "HTTPS to S3 and AWS services (Glue needs this for scripts, data, and API calls)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ciot-glue-sg-${var.environment}"
  }
}

# Egress rule for Glue to RDS (added separately to avoid cycle)
resource "aws_security_group_rule" "glue_to_rds" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.glue.id
  description              = "PostgreSQL to RDS"
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "ciot-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ciot-glue-role-${var.environment}"
  }
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3, RDS, and ENI management
resource "aws_iam_role_policy" "glue_s3_rds" {
  name = "ciot-glue-s3-rds-policy-${var.environment}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.buoy_data.arn}/raw/*",
          "${aws_s3_bucket.buoy_data.arn}/cleaned/*",
          "${aws_s3_bucket.buoy_data.arn}/processed/*",
          "${aws_s3_bucket.buoy_data.arn}/scripts/*",
          "${aws_s3_bucket.buoy_data.arn}/temp/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.buoy_data.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = data.aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}

# Glue Connection to RDS
# Uses credentials from pre-created Secrets Manager secret
# Based on approach from: https://github.com/cthdarren/50046-iot-project
resource "aws_glue_connection" "rds" {
  # Ensure RDS is fully available before creating Glue connection
  depends_on = [aws_db_instance.main]

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:postgresql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
    USERNAME            = local.rds_credentials.username
    PASSWORD            = local.rds_credentials.password
  }

  name = "ciot-rds-connection-${var.environment}"

  physical_connection_requirements {
    availability_zone      = var.availability_zones[0]
    security_group_id_list = [aws_security_group.glue.id]
    subnet_id              = aws_subnet.private[0].id
  }

  tags = {
    Name        = "ciot-rds-connection-${var.environment}"
    Environment = var.environment
  }
}

# Glue Job to Test RDS Connection
resource "aws_glue_job" "test_rds_connection" {
  name     = "ciot-test-rds-connection-${var.environment}"
  role_arn = aws_iam_role.glue_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.buoy_data.bucket}/scripts/test_rds_connection.py"
    python_version  = "3"
  }

  connections = [aws_glue_connection.rds.name]

  default_arguments = {
    "--TempDir"        = "s3://${aws_s3_bucket.buoy_data.bucket}/temp/"
    "--job-language"   = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--CONNECTION_NAME" = aws_glue_connection.rds.name
  }

  glue_version = "4.0"

  tags = {
    Name        = "ciot-test-rds-connection-${var.environment}"
    Environment = var.environment
  }
}

