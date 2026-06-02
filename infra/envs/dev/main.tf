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

resource "aws_lambda_function" "ingestion" {
    function_name = "${var.project_name}-ingestion"
    role          = aws_iam_role.lambda_role.arn
    handler       = "handler.handler"
    runtime       = "nodejs20.x"

    filename      = "../../../artifacts/ingestion/function.zip"
    source_code_hash = filebase64sha256("../../../artifacts/ingestion/function.zip")

    timeout = 10
    memory_size = 256

    environment {
        variables = {
            SQS_QUEUE_URL = aws_sqs_queue.events.url
            METRICS_NAMESPACE = "ObservabilityPlatform"
        }
    }

    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}
resource "aws_iam_role_policy" "lambda_sqs_send" {
    name = "${var.project_name}-lambda-sqs-send"
    role = aws_iam_role.lambda_role.id

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

    filename      = "../../../artifacts/processor/function.zip"
    source_code_hash = filebase64sha256("../../../artifacts/processor/function.zip")

    timeout = 10
    memory_size = 256

    environment {
        variables = {
            IDEMPOTENCY_TABLE_NAME   = aws_dynamodb_table.idempotency.name
            METRICS_NAMESPACE = "ObservabilityPlatform"
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

resource "aws_apigatewayv2_route" "events_post" {
    api_id    = aws_apigatewayv2_api.events_api.id
    route_key = "POST /events"
    target = "integrations/${aws_apigatewayv2_integration.lambda_ingestion.id}"

     authorizer_id = aws_apigatewayv2_authorizer.cognito_jwt.id
     authorization_type = "JWT"
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


resource "aws_lambda_permission" "apigateway_invoke" {
    statement_id  = "AllowExecutionFromAPIGatewayIngestion"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.ingestion.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.events_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "lambda_ingestion" {
    api_id           = aws_apigatewayv2_api.events_api.id
    integration_type = "AWS_PROXY"

    integration_uri = aws_lambda_function.ingestion.invoke_arn
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

resource "aws_cognito_user_pool" "main" {
    name = "${var.project_name}-user-pool"
    
    tags = {
        Project = var.project_name
        Environment = "dev"
        ManagedBy = "terraform"
    }
}

resource "aws_cognito_resource_server" "api_events" {
    identifier   = "${var.project_name}-api"
    name         = "${var.project_name}-resource-server"
    user_pool_id = aws_cognito_user_pool.main.id

    scope {
        scope_name        = "write"
        scope_description = "Send Events"
    }
}

resource "aws_cognito_user_pool_client" "app_user" {
    name                 = "${var.project_name}-api-client"
    user_pool_id         = aws_cognito_user_pool.main.id

    allowed_oauth_flows_user_pool_client = true
    allowed_oauth_flows = ["client_credentials"]
    allowed_oauth_scopes = ["${aws_cognito_resource_server.api_events.identifier}/write"]
    generate_secret = true
    explicit_auth_flows = []

}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
    api_id = aws_apigatewayv2_api.events_api.id
    name   = "${var.project_name}-cognito-authorizer"
    authorizer_type = "JWT"
    identity_sources = ["$request.header.Authorization"]

    jwt_configuration {
        audience = [aws_cognito_user_pool_client.app_user.id]
        issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    }
}

resource "aws_cognito_user_pool_domain" "main" {
    domain       = "${var.project_name}-auth"
    user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cloudwatch_dashboard" "main" {
    dashboard_name = "${var.project_name}-system-health"

    dashboard_body = jsonencode({
        widgets = [
            # Row 1: System Overview
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 0
                y      = 0
                properties = {
                    metrics = [
                        ["ObservabilityPlatform", "EventProcessed", "Service", "processor", { stat = "Sum", label = "Total Events Processed" }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Total Events Processed"
                    period = 900
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 8
                y      = 0
                properties = {
                    metrics = [
                        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.events.name, { stat = "Maximum", label = "Messages in Queue" }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Messages in Queue"
                    period = 300
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 16
                y      = 0
                properties = {
                    metrics = [
                        [{ expression = "m1+m2", label = "Total Failures", id = "e1", color = "#d62728" }],
                        ["ObservabilityPlatform", "EventRetried", "Service", "processor", { id = "m1", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventFailed", "Service", "ingestion", { id = "m2", stat = "Sum", visible = false }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Total Failures (3h)"
                    period = 900
                }
            },
            {
                type   = "metric"
                width  = 12
                height = 6
                x      = 0
                y      = 6
                properties = {
                    metrics = [
                        ["${var.project_name}/api-gateway", "${var.project_name}-Api4xxCount", { stat = "Sum", label = "4xx Errors", color = "#ff7f0e" }],
                        [".", "${var.project_name}-Api5xxCount", { stat = "Sum", label = "5xx Errors", color = "#d62728" }],
                        ["ObservabilityPlatform", "EventRejected", "Service", "ingestion", { stat = "Sum", label = "Rejected (bad payload)", color = "#9467bd" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "API Requests by Status"
                    period  = 60
                    yAxis = {
                        left = { min = 0 }
                    }
                    annotations = {
                        horizontal = [{
                            value = 5
                            label = "4xx Alarm Threshold"
                            fill  = "above"
                            color = "#ff7f0e"
                        }]
                    }
                }
            },
            {
                type   = "log"
                width  = 6
                height = 6
                x      = 12
                y      = 6
                properties = {
                    query   = "SOURCE '${aws_cloudwatch_log_group.api_gateway_logs.name}' | fields @timestamp, latency | stats avg(latency), pct(latency, 50), pct(latency, 99) by bin(5m)"
                    region  = var.region
                    title   = "API Latency (ms)"
                    stacked = false
                    view    = "timeSeries"
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 18
                y      = 6
                properties = {
                    metrics = [
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Average", label = "Avg Duration" }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "p99", label = "p99 Duration" }],
                        ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "Errors", yAxis = "right", color = "#d62728" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Ingestion Lambda Performance"
                    period  = 300
                    yAxis = {
                        left  = { label = "Duration (ms)", min = 0 }
                        right = { label = "Errors", min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 0
                y      = 12
                properties = {
                    metrics = [
                        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.events.name, { stat = "Maximum", label = "Max Depth" }],
                        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.events.name, { stat = "Average", label = "Avg Depth" }]
                    ]
                    view    = "timeSeries"
                    stacked = true
                    region  = var.region
                    title   = "SQS Queue Depth"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 8
                y      = 12
                properties = {
                    metrics = [
                        ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.events.name, { stat = "Maximum", label = "Queue Lag" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Queue Age (seconds)"
                    period  = 60
                    yAxis = {
                        left = { min = 0 }
                    }
                    annotations = {
                        horizontal = [{
                            value = 120
                            label = "2min Threshold"
                            fill  = "above"
                            color = "#d62728"
                        }]
                    }
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 16
                y      = 12
                properties = {
                    metrics = [
                        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.events-dlq.name, { stat = "Maximum", label = "DLQ Messages" }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Dead Letter Queue"
                    period = 300
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 0
                y      = 18
                properties = {
                    metrics = [
                        ["ObservabilityPlatform", "EventIngested", "Service", "ingestion", { stat = "Sum", label = "Ingested", color = "#2ca02c" }],
                        ["ObservabilityPlatform", "EventProcessed", "Service", "processor", { stat = "Sum", label = "Processed", color = "#1f77b4" }],
                        ["ObservabilityPlatform", "EventRejected", "Service", "processor", { stat = "Sum", label = "Rejected (schema)", color = "#9467bd" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Processing Throughput (events/min)"
                    period  = 60
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 6
                y      = 18
                properties = {
                    metrics = [
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Average", label = "Avg Duration" }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.processor.function_name, { stat = "p99", label = "p99 Duration" }],
                        ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Sum", label = "Errors", yAxis = "right", color = "#d62728" }],
                        ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Maximum", label = "Concurrency", yAxis = "right", color = "#9467bd" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Processor Lambda Health"
                    period  = 300
                    yAxis = {
                        left  = { label = "Duration (ms)", min = 0 }
                        right = { label = "Count", min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 12
                y      = 18
                properties = {
                    metrics = [
                        ["AWS/DynamoDB", "UserErrors", "TableName", aws_dynamodb_table.idempotency.name, { stat = "Sum", label = "User Errors" }],
                        ["AWS/DynamoDB", "SystemErrors", "TableName", aws_dynamodb_table.idempotency.name, { stat = "Sum", label = "System Errors", color = "#d62728" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "DynamoDB Idempotency Table Errors"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "alarm"
                width  = 6
                height = 6
                x      = 18
                y      = 18
                properties = {
                    title  = "Alarm Status"
                    alarms = [
                        aws_cloudwatch_metric_alarm.api_4xx_spike.arn,
                        aws_cloudwatch_metric_alarm.lambda_errors.arn,
                        aws_cloudwatch_metric_alarm.dlq_depth.arn,
                        aws_cloudwatch_metric_alarm.queue_lag.arn
                    ]
                }
            },
            # Row 5: Event Loss Detection
            {
                type   = "metric"
                width  = 12
                height = 6
                x      = 0
                y      = 24
                properties = {
                    metrics = [
                        ["ObservabilityPlatform", "EventIngested",  "Service", "ingestion",  { id = "m1", stat = "Sum", label = "Ingested",    color = "#2ca02c" }],
                        ["ObservabilityPlatform", "EventProcessed", "Service", "processor",  { id = "m2", stat = "Sum", label = "Processed",   color = "#1f77b4" }],
                        ["ObservabilityPlatform", "EventRejected",  "Service", "processor",  { id = "m3", stat = "Sum", label = "Rejected",    color = "#d62728" }],
                        ["ObservabilityPlatform", "EventDuplicated","Service", "processor",  { id = "m4", stat = "Sum", label = "Duplicated",  color = "#ff7f0e" }],
                        ["ObservabilityPlatform", "EventRetried",   "Service", "processor",  { id = "m5", stat = "Sum", label = "Retried",     color = "#e377c2" }],
                        [{ expression = "FILL(m1,0)-FILL(m2,0)-FILL(m3,0)-FILL(m4,0)-FILL(m5,0)", label = "Potential Loss", id = "e1", color = "#8c564b" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Event Flow & Loss Detection"
                    period  = 60
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 12
                y      = 24
                properties = {
                    metrics = [
                        [{ expression = "FILL(m1,0)-FILL(m2,0)-FILL(m3,0)-FILL(m4,0)-FILL(m5,0)", label = "Events Lost (24h)", id = "e1" }],
                        ["ObservabilityPlatform", "EventIngested",  "Service", "ingestion", { id = "m1", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventProcessed", "Service", "processor", { id = "m2", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventRejected",  "Service", "processor", { id = "m3", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventDuplicated","Service", "processor", { id = "m4", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventRetried",   "Service", "processor", { id = "m5", stat = "Sum", visible = false }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Potential Event Loss (24h)"
                    period = 86400
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 18
                y      = 24
                properties = {
                    metrics = [
                        [{ expression = "IF(m1>0, (m2/m1)*100, 0)", label = "Duplication Rate %", id = "e1" }],
                        ["ObservabilityPlatform", "EventIngested", "Service", "ingestion", { id = "m1", stat = "Sum", visible = false }],
                        ["ObservabilityPlatform", "EventDuplicated", "Service", "processor", { id = "m2", stat = "Sum", visible = false }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Duplication Rate %"
                    period = 900
                }
            },
            # Row 6: Throttling & Limits
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 0
                y      = 30
                properties = {
                    metrics = [
                        ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "Ingestion" }],
                        ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Sum", label = "Processor" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Lambda Throttle Events"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                    annotations = {
                        horizontal = [{
                            value = 1
                            label = "Any throttle is critical"
                            fill  = "above"
                            color = "#d62728"
                        }]
                    }
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 8
                y      = 30
                properties = {
                    metrics = [
                        ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Maximum", label = "Processor Concurrency" }],
                        ["AWS/Lambda", "UnreservedConcurrentExecutions", { stat = "Maximum", label = "Account Unreserved" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "Lambda Concurrency vs Limits"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                    annotations = {
                        horizontal = [{
                            value = 900
                            label = "Approaching limit (1000)"
                            fill  = "above"
                            color = "#ff7f0e"
                        }]
                    }
                }
            },
            {
                type   = "metric"
                width  = 8
                height = 6
                x      = 16
                y      = 30
                properties = {
                    metrics = [
                        ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", aws_dynamodb_table.idempotency.name, { stat = "Sum", label = "Write Throttles" }]
                    ]
                    view    = "timeSeries"
                    stacked = false
                    region  = var.region
                    title   = "DynamoDB Write Throttles"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                    annotations = {
                        horizontal = [{
                            value = 1
                            label = "Should be 0 (PAY_PER_REQUEST)"
                            fill  = "above"
                            color = "#d62728"
                        }]
                    }
                }
            },
            # Row 7: FinOps Cost Indicators
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 0
                y      = 36
                properties = {
                    metrics = [
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "Ingestion" }],
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.processor.function_name, { stat = "Sum", label = "Processor" }]
                    ]
                    view    = "timeSeries"
                    stacked = true
                    region  = var.region
                    title   = "Lambda Invocations (Cost: $0.20/1M)"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 6
                y      = 36
                properties = {
                    metrics = [
                        [{ expression = "(m1/1000)*(256/1024)*i1", label = "Ingestion GB-sec", id = "e1", color = "#1f77b4" }],
                        [{ expression = "(m2/1000)*(256/1024)*i2", label = "Processor GB-sec", id = "e2", color = "#ff7f0e" }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingestion.function_name, { id = "m1", stat = "Average", visible = false }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.processor.function_name, { id = "m2", stat = "Average", visible = false }],
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name, { id = "i1", stat = "Sum", visible = false }],
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.processor.function_name, { id = "i2", stat = "Sum", visible = false }]
                    ]
                    view    = "timeSeries"
                    stacked = true
                    region  = var.region
                    title   = "Lambda GB-seconds (Cost: $0.0000166667/GB-sec)"
                    period  = 300
                    yAxis = {
                        left = { min = 0 }
                    }
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 12
                y      = 36
                properties = {
                    metrics = [
                        [{ expression = "m1+m2", label = "Total SQS Requests", id = "e1" }],
                        ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.events.name, { id = "m1", stat = "Sum", visible = false }],
                        ["AWS/SQS", "NumberOfMessagesReceived", "QueueName", aws_sqs_queue.events.name, { id = "m2", stat = "Sum", visible = false }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "SQS API Calls (24h) - 1M free, then $0.40/1M"
                    period = 86400
                }
            },
            {
                type   = "metric"
                width  = 6
                height = 6
                x      = 18
                y      = 36
                properties = {
                    metrics = [
                        [{ expression = "(i1+i2)*0.0000002 + (m1*i1+m2*i2)*0.000000004166675", label = "Est. Daily Cost (USD)", id = "e1", color = "#2ca02c" }],
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name, { id = "i1", stat = "Sum", visible = false }],
                        ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.processor.function_name, { id = "i2", stat = "Sum", visible = false }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingestion.function_name, { id = "m1", stat = "Average", visible = false }],
                        ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.processor.function_name, { id = "m2", stat = "Average", visible = false }]
                    ]
                    view   = "singleValue"
                    region = var.region
                    title  = "Estimated Daily Lambda Cost"
                    period = 86400
                }
            }
        ]
    })
}
output "dashboard_url" {
    description = "CloudWatch Dashboard URL"
    value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

