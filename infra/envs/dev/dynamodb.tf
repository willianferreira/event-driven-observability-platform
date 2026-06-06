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

  tags = local.common_tags
}

resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }

  tags = local.common_tags
}
