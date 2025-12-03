# api-gateway

output "ingest_api_url" {
    value = aws_apigatewayv2_api.ingest_api.api_endpoint
}

# RDS Database

output "rds_endpoint" {
    description = "RDS instance endpoint"
    value       = aws_db_instance.main.endpoint
}

output "rds_address" {
    description = "RDS instance address"
    value       = aws_db_instance.main.address
}

output "rds_port" {
    description = "RDS instance port"
    value       = aws_db_instance.main.port
}

output "rds_database_name" {
    description = "RDS database name"
    value       = aws_db_instance.main.db_name
}

output "rds_master_user_secret_arn" {
    description = "ARN of the secret in AWS Secrets Manager containing the master password"
    value       = data.aws_secretsmanager_secret.rds_credentials.arn
    sensitive   = true
}

# ECR Repository
output "ecr_repository_url" {
    description = "URL of the ECR repository"
    value       = aws_ecr_repository.backend.repository_url
}

# ECS Cluster
output "ecs_cluster_name" {
    description = "Name of the ECS cluster"
    value       = aws_ecs_cluster.main.name
}

# Application Load Balancer
output "alb_dns_name" {
    description = "DNS name of the Application Load Balancer (for ESP32 access)"
    value       = aws_lb.backend.dns_name
}

output "backend_api_url" {
    description = "Full URL for ESP32 to send data"
    value       = "http://${aws_lb.backend.dns_name}"
}