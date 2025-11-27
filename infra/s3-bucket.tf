# S3 bucket 
resource "aws_s3_bucket" "buoy_data" {
  bucket = "ciot-buoy-data-${var.environment}"
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