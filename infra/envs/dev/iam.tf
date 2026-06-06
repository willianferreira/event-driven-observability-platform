resource "aws_iam_role" "lambda_ingestion" {
  name = "${var.project_name}-lambda-ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_ingestion" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sqs_send" {
  name = "${var.project_name}-lambda-sqs-send"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:SendMessage"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.events.arn
      }
    ]
  })
}

resource "aws_iam_role" "lambda_processing" {
  name = "${var.project_name}-lambda-processing"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_processing" {
  role       = aws_iam_role.lambda_processing.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_sqs_policy" {
  name = "${var.project_name}-lambda-sqs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.events.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_sqs" {
  role       = aws_iam_role.lambda_processing.name
  policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-lambda-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:TransactWriteItems"
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.idempotency.arn,
          aws_dynamodb_table.orders.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_dynamodb" {
  role       = aws_iam_role.lambda_processing.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}
