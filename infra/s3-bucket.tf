# S3 bucket 
resource "aws_s3_bucket" "buoy_data" {
  bucket = "ciot-buoy-data-${var.environment}"
  force_destroy = true
}

# "raw/" folder
resource "aws_s3_object" "raw_prefix" {
  bucket = aws_s3_bucket.buoy_data.id
  key = "raw/"
  acl = "private"   # only bucket owner can read
}

# "cleaned/" folder
resource "aws_s3_object" "cleaned_prefix" {
  bucket = aws_s3_bucket.buoy_data.id
  key = "cleaned/"
  acl = "private" 
}

# "processed/" folder
resource "aws_s3_object" "processed_prefix" {
  bucket = aws_s3_bucket.buoy_data.id
  key = "processed/"  # data coming out from AWS Glue
  acl = "private"
}

# "scripts/" folder for Glue job scripts
resource "aws_s3_object" "scripts_prefix" {
  bucket = aws_s3_bucket.buoy_data.id
  key = "scripts/"
  acl = "private"
}

# "temp/" folder for Glue temporary files
resource "aws_s3_object" "temp_prefix" {
  bucket = aws_s3_bucket.buoy_data.id
  key = "temp/"
  acl = "private"
}