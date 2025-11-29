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