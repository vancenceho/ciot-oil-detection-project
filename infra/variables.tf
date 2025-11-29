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
    default = "lambda_ingest.zip"
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
    description = "Master password for RDS database (not used when manage_master_user_password is true - AWS generates password automatically)"
    type = string
    sensitive = true
    default = null
}