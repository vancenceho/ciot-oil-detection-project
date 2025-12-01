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

output "rds_secret_arn" {
    description = "ARN of the secret in AWS Secrets Manager containing the RDS credentials"
    value       = data.aws_secretsmanager_secret.rds_credentials.arn
    sensitive   = true
}

# Glue Connection

output "glue_connection_name" {
    description = "Name of the Glue connection to RDS"
    value       = aws_glue_connection.rds.name
}

output "glue_connection_id" {
    description = "ID of the Glue connection"
    value       = aws_glue_connection.rds.id
}

output "glue_job_name" {
    description = "Name of the test Glue job"
    value       = aws_glue_job.test_rds_connection.name
}

output "s3_bucket_name" {
    description = "Name of the S3 bucket for scripts and data"
    value       = aws_s3_bucket.buoy_data.bucket
}