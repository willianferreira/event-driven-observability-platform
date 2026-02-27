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
}