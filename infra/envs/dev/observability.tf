resource "aws_cloudwatch_log_group" "core" {
  name              = "/${var.project_name}/core"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.project_name}-events-api"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_metric_filter" "api_4xx" {
  name           = "${var.project_name}-api-4xx"
  log_group_name = aws_cloudwatch_log_group.api_gateway_logs.name
  pattern        = "{ $.status = 4* }"
  metric_transformation {
    name      = "${var.project_name}-Api4xxCount"
    namespace = "${var.project_name}/api-gateway"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "api_5xx" {
  name           = "${var.project_name}-api-5xx"
  log_group_name = aws_cloudwatch_log_group.api_gateway_logs.name
  pattern        = "{ $.status = 5* }"

  metric_transformation {
    name      = "${var.project_name}-Api5xxCount"
    namespace = "${var.project_name}/api-gateway"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_4xx_spike" {
  alarm_name          = "${var.project_name}-api-4xx-spike"
  alarm_description   = "Triggers when API Gateway 4xx responses spike"
  namespace           = "${var.project_name}/api-gateway"
  metric_name         = "${var.project_name}-Api4xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  alarm_description   = "Triggers when Lambda function reports errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}


resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.project_name}-dlq-depth"
  alarm_description   = "Triggers when SQS DLQ has messages waiting"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    QueueName = aws_sqs_queue.events_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "queue_lag" {
  alarm_name          = "${var.project_name}-queue-lag"
  alarm_description   = "Messages stuck in SQS queue for too long"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 120
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    QueueName = aws_sqs_queue.events.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
