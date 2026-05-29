output "api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.dashboard.name
}

output "ingester_function_name" {
  value = aws_lambda_function.ingester.function_name
}

output "analyzer_function_name" {
  value = aws_lambda_function.analyzer.function_name
}

output "llm_ingester_function_name" {
  value = aws_lambda_function.llm_ingester.function_name
}
