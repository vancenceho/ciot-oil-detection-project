# iam role for lambda function 
resource "aws_iam_role" "ingest_lambda_role" {
    name = "oil-data-ingest-lambda-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = { Service = "lambda.amazonaws.com" }
        }]
    })
}

# policy so lambda can write to S3
resource "aws_iam_role_policy" "ingest_lambda_s3_policy" {
    name = "oil-data-ingest-s3-policy"
    role = aws_iam_role.ingest_lambda_role.id

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow" 
                Action = ["s3:PutObject"]
                Resource = "${aws_s3_bucket.buoy_data.arn}/raw/*"
            },
            {
                Effect = "Allow"
                Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
                Resource = "*"
            }
        ]
    })
}

# IAM Role for ECS Task Execution (pulls images, writes logs)
resource "aws_iam_role" "ecs_execution_role" {
  name = "ciot-ecs-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ciot-ecs-execution-role-${var.environment}"
    Environment = var.environment
  }
}

# IAM Policy for ECS Execution Role
resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  name = "ciot-ecs-execution-policy-${var.environment}"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.backend.arn}:*",
          "${aws_cloudwatch_log_group.frontend.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          data.aws_secretsmanager_secret.rds_credentials.arn
        ]
      }
    ]
  })
}

# IAM Role for ECS Task (application permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "ciot-ecs-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ciot-ecs-task-role-${var.environment}"
    Environment = var.environment
  }
}

# IAM Policy for ECS Task Role (add permissions your backend needs)
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "ciot-ecs-task-policy-${var.environment}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.buoy_data.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.backend.arn}:*",
          "${aws_cloudwatch_log_group.frontend.arn}:*"
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
        Action = ["secretsmanager:GetSecretValue"]
        Resource = data.aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}



