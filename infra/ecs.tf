# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "ciot-ecs-tasks-sg-${var.environment}"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ciot-ecs-tasks-sg-${var.environment}"
    Environment = var.environment
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "ciot-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "ciot-ecs-cluster-${var.environment}"
    Environment = var.environment
  }
}

# ECS Task Definition for Backend Service
resource "aws_ecs_task_definition" "backend" {
  family                   = "ciot-backend-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${aws_ecr_repository.backend.repository_url}:latest"

      portMappings = [
        {
          containerPort = var.backend_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "RDS_HOST"
          value = aws_db_instance.main.address
        },
        {
          name  = "RDS_PORT"
          value = tostring(aws_db_instance.main.port)
        },
        {
          name  = "RDS_DB_NAME"
          value = aws_db_instance.main.db_name
        },
        {
          name  = "RDS_SECRET_ARN"
          value = data.aws_secretsmanager_secret.rds_credentials.arn
        },
        {
          name = "S3_BUCKET"
          value = aws_s3_bucket.buoy_data.bucket
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.backend_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "ciot-backend-task-${var.environment}"
    Environment = var.environment
  }
}

# ECS Service
resource "aws_ecs_service" "backend" {
  name            = "ciot-backend-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = var.backend_port
  }

  depends_on = [
    aws_lb_listener.backend,
    aws_iam_role_policy.ecs_execution_role_policy
  ]

  tags = {
    Name        = "ciot-backend-service-${var.environment}"
    Environment = var.environment
  }
}

# CloudWatch Log Group for ECS Tasks
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/ciot-backend-${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "ciot-backend-logs-${var.environment}"
    Environment = var.environment
  }
}

