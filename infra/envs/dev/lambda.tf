resource "aws_lambda_function" "ingestion" {
  function_name = "${var.project_name}-ingestion"
  role          = aws_iam_role.lambda_ingestion.arn
  handler       = "handler.handler"
  publish       = true
  runtime       = "nodejs20.x"

  filename         = "../../../artifacts/ingestion/function.zip"
  source_code_hash = filebase64sha256("../../../artifacts/ingestion/function.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = {
      SQS_QUEUE_URL     = aws_sqs_queue.events.url
      METRICS_NAMESPACE = "ObservabilityPlatform"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_alias" "ingestion_live" {
  name             = "live"
  description      = "Stable alias for API Gateway ingestion traffic"
  function_name    = aws_lambda_function.ingestion.function_name
  function_version = coalesce(var.ingestion_alias_function_version, aws_lambda_function.ingestion.version)
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor"
  role          = aws_iam_role.lambda_processing.arn
  handler       = "handler.handler"
  publish       = true
  runtime       = "nodejs20.x"

  filename         = "../../../artifacts/processor/function.zip"
  source_code_hash = filebase64sha256("../../../artifacts/processor/function.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = {
      IDEMPOTENCY_TABLE_NAME = aws_dynamodb_table.idempotency.name
      ORDERS_TABLE_NAME      = aws_dynamodb_table.orders.name
      METRICS_NAMESPACE      = "ObservabilityPlatform"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_alias" "processor_live" {
  name             = "live"
  description      = "Stable alias for SQS processor traffic"
  function_name    = aws_lambda_function.processor.function_name
  function_version = coalesce(var.processor_alias_function_version, aws_lambda_function.processor.version)
}

resource "aws_lambda_function" "orders_query" {
  function_name = "${var.project_name}-orders-query"
  role          = aws_iam_role.lambda_orders_query.arn
  handler       = "handler.handler"
  runtime       = "nodejs20.x"

  filename         = "../../../artifacts/orders-query/function.zip"
  source_code_hash = filebase64sha256("../../../artifacts/orders-query/function.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = {
      ORDERS_TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }

  tags = local.common_tags
}
