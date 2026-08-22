locals {
  project     = "cost-dashboard"
  environment = var.environment
  region      = var.region

  # Keys are TitleCase to match required_tags and provider default_tags.
  # Provider default_tags already applies these account-wide; kept here so
  # per-resource tags stay identical (no lowercase duplicate keys).
  common_tags = {
    Project     = local.project
    Environment = local.environment
    Owner       = "jordann6"
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
    Team        = var.team
  }
}

# --- DynamoDB (single-table) --------------------------------------------------

resource "aws_dynamodb_table" "dashboard" {
  name         = "${local.project}-${local.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = local.common_tags
}

# --- SNS Alerts ---------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.project}-alerts-${local.environment}"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- IAM: shared assume policy ------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- IAM: Ingester ------------------------------------------------------------

resource "aws_iam_role" "ingester" {
  name               = "role-${local.project}-ingester-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "ingester" {
  statement {
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetReservationCoverage",
      "ce:GetSavingsPlansCoverage",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }
  # Read-only describes for the waste scan (idle EBS / EIP, gp2 volumes).
  statement {
    actions   = ["ec2:DescribeVolumes", "ec2:DescribeAddresses"]
    resources = ["*"]
  }
  statement {
    actions   = ["dynamodb:Query", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:BatchWriteItem"]
    resources = [aws_dynamodb_table.dashboard.arn]
  }
}

resource "aws_iam_role_policy" "ingester" {
  name   = "ingester-policy"
  role   = aws_iam_role.ingester.id
  policy = data.aws_iam_policy_document.ingester.json
}

resource "aws_iam_role_policy_attachment" "ingester_basic" {
  role       = aws_iam_role.ingester.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- IAM: Analyzer ------------------------------------------------------------

resource "aws_iam_role" "analyzer" {
  name               = "role-${local.project}-analyzer-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "analyzer" {
  statement {
    actions   = ["dynamodb:Query", "dynamodb:PutItem", "dynamodb:BatchWriteItem"]
    resources = [aws_dynamodb_table.dashboard.arn]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "analyzer" {
  name   = "analyzer-policy"
  role   = aws_iam_role.analyzer.id
  policy = data.aws_iam_policy_document.analyzer.json
}

resource "aws_iam_role_policy_attachment" "analyzer_basic" {
  role       = aws_iam_role.analyzer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- IAM: API -----------------------------------------------------------------

resource "aws_iam_role" "api" {
  name               = "role-${local.project}-api-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "api" {
  statement {
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.dashboard.arn]
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "api-policy"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Functions ---------------------------------------------------------

data "archive_file" "ingester" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ingester.py"
  output_path = "${path.module}/ingester.zip"
}

data "archive_file" "analyzer" {
  type        = "zip"
  source_file = "${path.module}/../lambda/analyzer.py"
  output_path = "${path.module}/analyzer.zip"
}

data "archive_file" "api_fn" {
  type        = "zip"
  source_file = "${path.module}/../lambda/api.py"
  output_path = "${path.module}/api.zip"
}

resource "aws_lambda_function" "ingester" {
  function_name    = "lambda-${local.project}-ingester-${local.environment}"
  role             = aws_iam_role.ingester.arn
  handler          = "ingester.handler"
  runtime          = "python3.12"
  timeout          = 300
  filename         = data.archive_file.ingester.output_path
  source_code_hash = data.archive_file.ingester.output_base64sha256

  environment {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.dashboard.name
      REQUIRED_TAGS = jsonencode(var.required_tags)
      COST_TAG_KEY  = "Project"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "analyzer" {
  function_name    = "lambda-${local.project}-analyzer-${local.environment}"
  role             = aws_iam_role.analyzer.arn
  handler          = "analyzer.handler"
  runtime          = "python3.12"
  timeout          = 300
  filename         = data.archive_file.analyzer.output_path
  source_code_hash = data.archive_file.analyzer.output_base64sha256

  environment {
    variables = {
      TABLE_NAME      = aws_dynamodb_table.dashboard.name
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "api" {
  function_name    = "lambda-${local.project}-api-${local.environment}"
  role             = aws_iam_role.api.arn
  handler          = "api.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.api_fn.output_path
  source_code_hash = data.archive_file.api_fn.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dashboard.name
    }
  }

  tags = local.common_tags
}

# --- EventBridge Scheduler ---------------------------------------------------

resource "aws_scheduler_schedule_group" "dashboard" {
  name = "${local.project}-${local.environment}"
  tags = local.common_tags
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "role-${local.project}-scheduler-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.ingester.arn,
      aws_lambda_function.analyzer.arn,
      aws_lambda_function.llm_ingester.arn,
    ]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "invoke-lambdas"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

# Ingester runs at 01:00 UTC, analyzer at 02:00 UTC (after ingestion completes)
resource "aws_scheduler_schedule" "ingest" {
  name       = "daily-ingest"
  group_name = aws_scheduler_schedule_group.dashboard.name

  flexible_time_window { mode = "OFF" }
  schedule_expression          = "cron(0 1 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.ingester.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

resource "aws_scheduler_schedule" "analyze" {
  name       = "daily-analyze"
  group_name = aws_scheduler_schedule_group.dashboard.name

  flexible_time_window { mode = "OFF" }
  schedule_expression          = "cron(0 2 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.analyzer.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# --- API Gateway (HTTP) -------------------------------------------------------

resource "aws_apigatewayv2_api" "dashboard" {
  name          = "api-${local.project}-${local.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.dashboard.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.dashboard.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "costs" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /costs"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "anomalies" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /anomalies"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "forecast" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /forecast"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "tags" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /tags"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "costs_by_tag" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /costs-by-tag"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "coverage" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /coverage"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "waste" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /waste"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard.execution_arn}/*/*"
}

# --- LLM Gateway Cost Ingester -----------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  llm_gateway_table_arn = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.llm_gateway_table_name}"
}

resource "aws_iam_role" "llm_ingester" {
  name               = "role-${local.project}-llm-ingester-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "llm_ingester" {
  statement {
    actions   = ["dynamodb:Scan"]
    resources = [local.llm_gateway_table_arn]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
    resources = [aws_dynamodb_table.dashboard.arn]
  }
}

resource "aws_iam_role_policy" "llm_ingester" {
  name   = "llm-ingester-policy"
  role   = aws_iam_role.llm_ingester.id
  policy = data.aws_iam_policy_document.llm_ingester.json
}

resource "aws_iam_role_policy_attachment" "llm_ingester_basic" {
  role       = aws_iam_role.llm_ingester.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "llm_ingester" {
  type        = "zip"
  source_file = "${path.module}/../lambda/llm_ingester.py"
  output_path = "${path.module}/llm_ingester.zip"
}

resource "aws_lambda_function" "llm_ingester" {
  function_name    = "lambda-${local.project}-llm-ingester-${local.environment}"
  role             = aws_iam_role.llm_ingester.arn
  handler          = "llm_ingester.handler"
  runtime          = "python3.12"
  timeout          = 120
  filename         = data.archive_file.llm_ingester.output_path
  source_code_hash = data.archive_file.llm_ingester.output_base64sha256

  environment {
    variables = {
      TABLE_NAME             = aws_dynamodb_table.dashboard.name
      LLM_GATEWAY_TABLE_NAME = var.llm_gateway_table_name
      AWS_REGION_VAR         = var.region
    }
  }

  tags = local.common_tags
}

# Runs at 00:30 UTC — before the AWS cost ingester at 01:00 UTC
resource "aws_scheduler_schedule" "llm_ingest" {
  name       = "daily-llm-ingest"
  group_name = aws_scheduler_schedule_group.dashboard.name

  flexible_time_window { mode = "OFF" }
  schedule_expression          = "cron(30 0 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.llm_ingester.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# --- S3 + CloudFront (React Frontend) ----------------------------------------

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.project}-ui-${local.environment}-${random_string.suffix.result}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.project}-oac-${local.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  tags                = local.common_tags

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # SPA fallback — S3 403/404 → serve index.html
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}
