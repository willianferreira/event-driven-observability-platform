resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  tags = local.common_tags
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
  name         = "${var.project_name}-api-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.api_events.identifier}/write"]
  generate_secret                      = true
  explicit_auth_flows                  = []

}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

