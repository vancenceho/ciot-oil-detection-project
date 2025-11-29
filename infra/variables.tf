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