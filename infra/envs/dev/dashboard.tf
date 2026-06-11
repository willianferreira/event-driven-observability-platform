resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-system-health"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Executive signals
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
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.events_dlq.name, { stat = "Maximum", label = "DLQ Messages" }]
          ]
          view   = "singleValue"
          region = var.region
          title  = "Dead Letter Queue"
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
            [{ expression = "FILL(m1,0)-FILL(m2,0)-FILL(m3,0)-FILL(m4,0)", label = "Unresolved Events (24h)", id = "e1" }],
            ["ObservabilityPlatform", "EventIngested", "Service", "ingestion", { id = "m1", stat = "Sum", visible = false }],
            ["ObservabilityPlatform", "EventProcessed", "Service", "processor", { id = "m2", stat = "Sum", visible = false }],
            ["ObservabilityPlatform", "EventRejected", "Service", "processor", { id = "m3", stat = "Sum", visible = false }],
            ["ObservabilityPlatform", "EventDuplicated", "Service", "processor", { id = "m4", stat = "Sum", visible = false }]
          ]
          view   = "singleValue"
          region = var.region
          title  = "Unresolved Events (24h)"
          period = 86400
        }
      },

      # Row 2: Entry point health
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
        type   = "metric"
        width  = 6
        height = 6
        x      = 12
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
        type   = "alarm"
        width  = 6
        height = 6
        x      = 18
        y      = 6
        properties = {
          title = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.api_4xx_spike.arn,
            aws_cloudwatch_metric_alarm.lambda_errors.arn,
            aws_cloudwatch_metric_alarm.dlq_depth.arn,
            aws_cloudwatch_metric_alarm.queue_lag.arn
          ]
        }
      },

      # Row 3: Queue and processor health
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

      # Row 4: Event flow and idempotency
      {
        type   = "metric"
        width  = 8
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
          title   = "Processing Throughput"
          period  = 60
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
        y      = 18
        properties = {
          metrics = [
            ["ObservabilityPlatform", "EventIngested", "Service", "ingestion", { id = "m1", stat = "Sum", label = "Ingested", color = "#2ca02c" }],
            ["ObservabilityPlatform", "EventProcessed", "Service", "processor", { id = "m2", stat = "Sum", label = "Processed", color = "#1f77b4" }],
            ["ObservabilityPlatform", "EventRejected", "Service", "processor", { id = "m3", stat = "Sum", label = "Rejected", color = "#d62728" }],
            ["ObservabilityPlatform", "EventDuplicated", "Service", "processor", { id = "m4", stat = "Sum", label = "Duplicated", color = "#ff7f0e" }],
            [{ expression = "FILL(m1,0)-FILL(m2,0)-FILL(m3,0)-FILL(m4,0)", label = "Unresolved Events", id = "e1", color = "#8c564b" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Event Flow & Unresolved Events"
          period  = 60
          yAxis = {
            left = { min = 0 }
          }
        }
      },
      {
        type   = "metric"
        width  = 8
        height = 6
        x      = 16
        y      = 18
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
      }
    ]
  })
}
