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
    value       = aws_db_instance.main.master_user_secret[0].secret_arn
    sensitive   = true
}