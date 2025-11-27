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