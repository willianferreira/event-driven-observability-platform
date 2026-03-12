terraform {
    required_version = ">= 1.14.5"

    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }

    backend "local" {}
}

provider "aws" {
    region = var.region
}

resource "aws_cloudwatch_log_group" "core" {
    name              = "/${var.project_name}/core"
    retention_in_days = 14
    
    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_sns_topic" "alerts" {
    name = "${var.project_name}-alerts"

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_sns_topic_subscription" "alerts_email" {
    topic_arn = aws_sns_topic.alerts.arn
    protocol  = "email"
    endpoint  = var.alerts_email
}

resource "aws_sqs_queue" "events-dlq" {
    name = "${var.project_name}-events-dlq"
    message_retention_seconds =  1209600 # 14 days in seconds

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_sqs_queue" "events" {
    name = "${var.project_name}-events"
    message_retention_seconds = 345600 # 4 days in seconds 
    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.events-dlq.arn
        maxReceiveCount     = 5
    })

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_iam_role" "lambda_role" {
    name = "${var.project_name}-lambda-role"

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

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
    role       = aws_iam_role.lambda_role.name
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
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}

resource "aws_lambda_function" "processor" {
    function_name = "${var.project_name}-processor"
    role          = aws_iam_role.lambda_role.arn
    handler       = "handler.handler"
    runtime       = "nodejs20.x"

    filename      = "../../../services/api/src/function.zip"
    source_code_hash = filebase64sha256("../../../services/api/src/function.zip")

    timeout = 10
    memory_size = 256

    environment {
        variables = {
            IDEMPOTENCY_TABLE_NAME   = aws_dynamodb_table.idempotency.name
        }
    }

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
    event_source_arn = aws_sqs_queue.events.arn
    function_name    = aws_lambda_function.processor.arn
    batch_size       = 5
    enabled          = true

    function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_dynamodb_table" "idempotency" {
    name         = "${var.project_name}-idempotency"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "eventId"
    ttl {
        attribute_name = "expiresAt"
        enabled        = true
    }

    attribute {
        name = "eventId"
        type = "S"
    }

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
    name = "${var.project_name}-lambda-dynamodb-policy"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = [
                    "dynamodb:PutItem"
                ]
                Effect   = "Allow"
                Resource = aws_dynamodb_table.idempotency.arn
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_dynamodb" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_apigatewayv2_api" "events_api" {
    name          = "${var.project_name}-events-api"
    protocol_type = "HTTP"

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_iam_role" "apigateway_sqs_role" {
    name = "${var.project_name}-apigateway-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "apigateway.amazonaws.com"
                }
            }
        ]
    })

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_iam_policy" "apigateway_sqs_policy" {
    name = "${var.project_name}-apigateway-sqs-policy"

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

resource "aws_iam_role_policy_attachment" "apigateway_attach_sqs" {
    role       = aws_iam_role.apigateway_sqs_role.name
    policy_arn = aws_iam_policy.apigateway_sqs_policy.arn
}

resource "aws_apigatewayv2_integration" "sqs_integration" {
    api_id           = aws_apigatewayv2_api.events_api.id
    integration_type = "AWS_PROXY"
    integration_subtype = "SQS-SendMessage"
    credentials_arn = aws_iam_role.apigateway_sqs_role.arn
    payload_format_version = "1.0"
    request_parameters = {
        QueueUrl = aws_sqs_queue.events.url
        MessageBody = "$request.body"
    }
}

resource "aws_apigatewayv2_route" "events_post" {
    api_id    = aws_apigatewayv2_api.events_api.id
    route_key = "POST /events"
    target    = "integrations/${aws_apigatewayv2_integration.sqs_integration.id}"
}

resource "aws_apigatewayv2_stage" "dev" {
    api_id      = aws_apigatewayv2_api.events_api.id
    name        = "dev"
    auto_deploy = true

    default_route_settings {
        throttling_rate_limit = 1
        throttling_burst_limit = 2
    }

    access_log_settings {
        destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
        format          = jsonencode({
            requestId       = "$context.requestId"
            ip              = "$context.identity.sourceIp"
            routeKey        = "$context.routeKey"
            requestTime     = "$context.requestTime"
            httpMethod      = "$context.httpMethod"
            resourcePath    = "$context.resourcePath"
            responseLength  = "$context.responseLength"
            latency         = "$context.integrationLatency"
            routeKey        = "$context.routeKey"
            status          = "$context.status"
            protocol        = "$context.protocol"
            integrationErrorMessage = "$context.integrationErrorMessage"
        })
    }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
    name              = "/aws/apigateway/${var.project_name}-events-api"
    retention_in_days = 7
    
    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_cloudwatch_log_metric_filter" "api_4xx" {
    name           = "${var.project_name}-api-4xx"
    log_group_name = aws_cloudwatch_log_group.api_gateway_logs.name
    pattern = "{ $.status = 4* }"
    metric_transformation {
        name      = "${var.project_name}-Api4xxCount"
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
    evaluation_periods  = 1 
    threshold           = 5
    comparison_operator = "GreaterThanOrEqualToThreshold"

    alarm_actions = [aws_sns_topic.alerts.arn]

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
    alarm_name          = "${var.project_name}-lambda-errors"
    alarm_description   = "Triggers when Lambda function reports errors"
    namespace           = "AWS/Lambda"
    metric_name         = "Errors"
    statistic           = "Sum"
    period              = 60
    evaluation_periods  = 1
    threshold           = 1
    comparison_operator = "GreaterThanOrEqualToThreshold"

    dimensions = {
        FunctionName = aws_lambda_function.processor.function_name
    }

    alarm_actions = [aws_sns_topic.alerts.arn]

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
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
    comparison_operator = "GreaterThanOrEqualToThreshold"

    dimensions = {
        QueueName = aws_sqs_queue.events-dlq.name
    }

    alarm_actions = [aws_sns_topic.alerts.arn]

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
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
    comparison_operator = "GreaterThanOrEqualToThreshold"

    dimensions = {
        QueueName = aws_sqs_queue.events.name
    }

    alarm_actions = [aws_sns_topic.alerts.arn]

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}