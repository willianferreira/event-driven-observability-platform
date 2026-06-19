resource "aws_sqs_queue" "events_dlq" {
  name                      = "${var.project_name}-events-dlq"
  message_retention_seconds = 1209600 # 14 days in seconds

  tags = local.common_tags
}

resource "aws_sqs_queue" "events" {
  name                      = "${var.project_name}-events"
  message_retention_seconds = 345600 # 4 days in seconds 
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 5
  })

  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_alias.processor_live.arn
  batch_size       = 5
  enabled          = true

  function_response_types = ["ReportBatchItemFailures"]

  tags = local.common_tags
}

