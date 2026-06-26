data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

# --- Plan Role ---

resource "aws_iam_role" "github_actions_plan" {
  name = "github-actions-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "github_plan_state" {
  name = "github-actions-plan-state"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

# --- Apply Role ---

resource "aws_iam_role" "github_actions_apply" {
  name = "github-actions-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_apply_permissions" {
  name = "github-actions-apply-permissions"
  role = aws_iam_role.github_actions_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaScoped"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "arn:aws:lambda:us-east-2:${data.aws_caller_identity.current.account_id}:function:event-driven-*"
      },
      {
        Sid    = "LambdaESM"
        Effect = "Allow"
        Action = [
          "lambda:CreateEventSourceMapping",
          "lambda:DeleteEventSourceMapping",
          "lambda:UpdateEventSourceMapping",
          "lambda:GetEventSourceMapping",
          "lambda:ListEventSourceMappings"
        ]
        Resource = "*"
      },
      {
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "arn:aws:apigateway:us-east-2::/*"
      },
      {
        Sid      = "Cognito"
        Effect   = "Allow"
        Action   = ["cognito-idp:*"]
        Resource = "arn:aws:cognito-idp:us-east-2:${data.aws_caller_identity.current.account_id}:userpool/*"
      },
      {
        Sid      = "SQS"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "arn:aws:sqs:us-east-2:${data.aws_caller_identity.current.account_id}:event-driven-*"
      },
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = "arn:aws:dynamodb:us-east-2:${data.aws_caller_identity.current.account_id}:table/event-driven-*"
      },
      {
        Sid      = "CloudWatch"
        Effect   = "Allow"
        Action   = ["cloudwatch:*", "logs:*"]
        Resource = "*"
      },
      {
        Sid      = "SNS"
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = "arn:aws:sns:us-east-2:${data.aws_caller_identity.current.account_id}:event-driven-*"
      },
      {
        Sid    = "IAMScoped"
        Effect = "Allow"
        Action = ["iam:*"]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/event-driven-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/event-driven-*"
        ]
      },
      {
        Sid      = "IAMMisc"
        Effect   = "Allow"
        Action   = ["iam:ListPolicies", "iam:GetOpenIDConnectProvider"]
        Resource = "*"
      },
      {
        Sid    = "S3State"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}
