variable "region" {
    description = "AWS region where the resources will be created" 
    type = string
    default = "ap-southeast-1"
}

variable "environment" {
    description = "Deployment environment" 
    type = string
    default = "dev"
}

variable "lambda_handler" {
    description = "lambda handler (file.function)"
    type = string
    default = "handler.lambda_handler"
}

variable "lambda_filename" {
    description = "lambda deployment package filename" 
    type = string
    default = "scripts/lambda_ingest.zip"
}

variable "vpc_cidr" {
    description = "CIDR block for VPC"
    type = string
    default = "10.0.0.0/16"
}

variable "availability_zones" {
    description = "Availability zones for subnets"
    type = list(string)
    default = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "db_password" {
    description = "Master password for RDS database (deprecated - password is now managed via Secrets Manager. Run ./scripts/setup-secrets.sh to create the secret)"
    type = string
    sensitive = true
    default = null
}

# ECS Configuration
variable "ecs_task_cpu" {
    description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
    type = number
    default = 512
}

variable "ecs_task_memory" {
    description = "Memory in MB for ECS task"
    type = number
    default = 2048
}

variable "ecs_desired_count" {
    description = "Desired number of ECS tasks"
    type = number
    default = 1
}

variable "backend_port" {
    description = "Port for backend service"
    type = number
    default = 8080
}