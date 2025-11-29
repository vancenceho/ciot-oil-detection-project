# HTTP API Gateway (v2)

resource "aws_apigatewayv2_api" "ingest_api" {
    name = "oil-data-ingest-api-${var.environment}"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "ingest_integration" {
    api_id = aws_apigatewayv2_api.ingest_api.id
    integration_type = "AWS_PROXY"
    integration_uri = aws_lambda_function.ingest.arn
    integration_method = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ingest_route" {
    api_id = aws_apigatewayv2_api.ingest_api.id
    route_key = "POST /ingest"
    target = "integrations/${aws_apigatewayv2_integration.ingest_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
    api_id = aws_apigatewayv2_api.ingest_api.id
    name = "$default"
    auto_deploy = true
}

# allow API Gateway to call lambda
resource "aws_lambda_permission" "allow_apigw" {
    statement_id = "AllowAPIGatewayInvoke"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.ingest.arn
    principal = "apigateway.amazonaws.com"
    source_arn = "${aws_apigatewayv2_api.ingest_api.execution_arn}/*/*"
}