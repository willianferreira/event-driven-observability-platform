resource "aws_apigatewayv2_api" "events_api" {
  name          = "${var.project_name}-events-api"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_route" "events_post" {
  api_id    = aws_apigatewayv2_api.events_api.id
  route_key = "POST /events"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_ingestion.id}"

  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.events_api.id
  name        = "dev"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 1
    throttling_burst_limit = 2
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      routeKey                = "$context.routeKey"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      responseLength          = "$context.responseLength"
      latency                 = "$context.integrationLatency"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}


resource "aws_lambda_permission" "apigateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGatewayIngestion"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  qualifier     = aws_lambda_alias.ingestion_live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.events_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "lambda_ingestion" {
  api_id           = aws_apigatewayv2_api.events_api.id
  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_alias.ingestion_live.invoke_arn
}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.events_api.id
  name             = "${var.project_name}-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app_user.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}
