# api-gateway

output "ingest_api_url" {
    value = aws_apigatewayv2_api.ingest_api.api_endpoint
}