# lambda function (zip/package must exist in s3 or locally)
resource "aws_lambda_function" "ingest" {
    function_name = "buoy-data-ingest-${var.environment}"
    role = aws_iam_role.ingest_lambda_role.arn
    runtime = "python3.11"

    filename = var.lambda_filename
    source_code_hash = filebase64sha256(var.lambda_filename)
    handler = var.lambda_handler

    environment {
        variables = {
            BUCKET_NAME = aws_s3_bucket.buoy_data.bucket
        }
    }
}