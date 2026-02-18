# =================================================================== locals ===

locals {
  enabled = module.this.enabled

  aws_account_id  = data.aws_caller_identity.current.account_id
  aws_region_name = data.aws_region.current.id
  aws_partition   = data.aws_partition.current.partition

  # use provided webhook secret or generate one
  github_webhook_secret = var.github_app_config.webhook_secret != "" ? var.github_app_config.webhook_secret : random_password.webhook_secret[0].result

  # use provided admin token or generate one (only if enabled)
  admin_token = var.admin_token_config.enabled ? (var.admin_token_config.token != "" ? var.admin_token_config.token : random_password.admin_token[0].result) : ""

  lambda_environment = merge(
    {
      # github app config
      APP_GITHUB_APP_ID          = var.github_app_config.app_id
      APP_GITHUB_APP_PRIVATE_KEY = var.github_app_config.private_key
      APP_GITHUB_INSTALLATION_ID = var.github_app_config.installation_id
      APP_GITHUB_ORG             = var.github_app_config.org
      APP_GITHUB_WEBHOOK_SECRET  = local.github_webhook_secret

      # api gateway config
      APP_BASE_PATH = var.api_gateway_config.enabled ? "/${var.api_gateway_config.stage_name}" : ""

      # pr compliance config
      APP_PR_COMPLIANCE_ENABLED = tostring(var.pr_compliance_config.enabled)
      APP_PR_MONITORED_BRANCHES = var.pr_compliance_config.enabled ? join(",", var.pr_compliance_config.monitored_branches) : ""

      # security alerts config
      APP_SECURITY_ALERTS_ENABLED = tostring(var.security_alerts_config.enabled)
    },
    var.security_alerts_config.enabled ? {
      APP_SECURITY_ALERTS_MIN_AGE_DAYS = tostring(var.security_alerts_config.min_age_days)
      APP_SECURITY_ALERTS_MIN_SEVERITY = var.security_alerts_config.min_severity
    } : {},
    # admin token config (conditional)
    local.admin_token != "" ? { APP_ADMIN_TOKEN = local.admin_token } : {},
    # okta config (conditional)
    var.okta_config.enabled ? merge({
      APP_OKTA_DOMAIN                      = var.okta_config.domain
      APP_OKTA_CLIENT_ID                   = var.okta_config.client_id
      APP_OKTA_PRIVATE_KEY                 = var.okta_config.private_key
      APP_OKTA_GITHUB_USER_FIELD           = var.okta_config.github_user_field
      APP_OKTA_SYNC_RULES                  = length(var.okta_config.sync_rules) > 0 ? jsonencode(var.okta_config.sync_rules) : ""
      APP_OKTA_SYNC_SAFETY_THRESHOLD       = tostring(var.okta_config.sync_safety_threshold)
      APP_OKTA_ORPHANED_USER_NOTIFICATIONS = tostring(var.okta_config.orphaned_user_notifications)
    }, var.okta_config.key_id != "" ? { APP_OKTA_KEY_ID = var.okta_config.key_id } : {}) : {},
    # slack config (conditional)
    var.slack_config.enabled ? merge({
      APP_SLACK_TOKEN   = var.slack_config.token
      APP_SLACK_CHANNEL = var.slack_config.channel
      },
      var.slack_config.channel_okta_sync != "" ? { APP_SLACK_CHANNEL_OKTA_SYNC = var.slack_config.channel_okta_sync } : {},
      var.slack_config.channel_orphaned_users != "" ? { APP_SLACK_CHANNEL_ORPHANED_USERS = var.slack_config.channel_orphaned_users } : {},
      var.slack_config.channel_security_alerts != "" ? { APP_SLACK_CHANNEL_SECURITY_ALERTS = var.slack_config.channel_security_alerts } : {},
      var.slack_config.channel_pr_bypass != "" ? {
        APP_SLACK_CHANNEL_PR_BYPASS     = var.slack_config.channel_pr_bypass
        APP_SLACK_FOOTER_NOTE_PR_BYPASS = var.pr_compliance_config.slack_footer_note
      } : {},
    ) : {},
    # additional environment variables
    var.lambda_environment_variables
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ======================================================== webhook secret ===

resource "random_password" "webhook_secret" {
  count = local.enabled && var.github_app_config.webhook_secret == "" ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "admin_token" {
  count = local.enabled && var.admin_token_config.enabled && var.admin_token_config.token == "" ? 1 : 0

  length  = 32
  special = false
}

# ================================================================== lambda ===

module "bot_artifact" {
  source = "github.com/cruxstack/terraform-docker-artifact-packager?ref=v1.4.0"

  count = local.enabled ? 1 : 0

  attributes             = ["lambda"]
  artifact_src_path      = "/tmp/package.zip"
  artifact_dst_directory = "${path.module}/dist"
  docker_build_context   = abspath("${path.module}/assets/lambda-function")
  docker_build_target    = "package"
  force_rebuild_id       = var.bot_force_rebuild_id

  docker_build_args = {
    BOT_VERSION = var.bot_version
    BOT_REPO    = var.bot_repo
  }

  context = module.this.context
}

resource "aws_lambda_function" "this" {
  count = local.enabled ? 1 : 0

  function_name                  = module.this.id
  description                    = "GitHub Ops App - Automates GitHub organization operations including Okta sync, PR compliance, and team management"
  role                           = aws_iam_role.this[0].arn
  handler                        = "bootstrap"
  runtime                        = var.lambda_config.runtime
  memory_size                    = var.lambda_config.memory_size
  timeout                        = var.lambda_config.timeout
  reserved_concurrent_executions = var.lambda_config.reserved_concurrent_executions
  architectures                  = [var.lambda_config.architecture]

  filename = module.bot_artifact[0].artifact_package_path

  environment {
    variables = local.lambda_environment
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.this,
    module.bot_artifact
  ]

  tags = module.this.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  count = local.enabled ? 1 : 0

  name              = "/aws/lambda/${module.this.id}"
  retention_in_days = var.lambda_log_retention_days
  tags              = module.this.tags
}

# ============================================================= api gateway ===

resource "aws_apigatewayv2_api" "this" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  name          = module.this.id
  protocol_type = "HTTP"
  description   = "API Gateway for GitHub Ops App webhooks"

  cors_configuration {
    allow_origins = var.api_gateway_config.cors_allow_origins
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["Content-Type", "X-Hub-Signature-256", "X-GitHub-Event", "X-GitHub-Delivery"]
    max_age       = 300
  }

  tags = module.this.tags
}

resource "aws_apigatewayv2_stage" "this" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = var.api_gateway_config.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationStatus = "$context.integrationStatus"
    })
  }

  tags = module.this.tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  name              = "/aws/apigateway/${module.this.id}"
  retention_in_days = var.lambda_log_retention_days
  tags              = module.this.tags
}

resource "aws_apigatewayv2_integration" "this" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.this[0].id}"
}

resource "aws_lambda_permission" "api_gateway" {
  count = local.enabled && var.api_gateway_config.enabled ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}

# ============================================================= eventbridge ===

resource "aws_cloudwatch_event_rule" "okta_sync" {
  count = local.enabled && var.okta_sync_schedule.enabled ? 1 : 0

  name                = "${module.this.id}-okta-sync"
  description         = "Scheduled trigger for Okta-GitHub team sync"
  schedule_expression = var.okta_sync_schedule.schedule_expression
  tags                = module.this.tags
}

resource "aws_cloudwatch_event_target" "okta_sync" {
  count = local.enabled && var.okta_sync_schedule.enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.okta_sync[0].name
  target_id = "OktaSyncLambda"
  arn       = aws_lambda_function.this[0].arn

  input_transformer {
    input_paths = {
      source      = "$.source"
      detail_type = "$.detail-type"
      time        = "$.time"
      region      = "$.region"
    }
    input_template = <<-EOF
      {
        "version": "0",
        "source": <source>,
        "detail-type": <detail_type>,
        "time": <time>,
        "region": <region>,
        "detail": {"action": "okta-sync"}
      }
    EOF
  }
}

resource "aws_lambda_permission" "eventbridge" {
  count = local.enabled && var.okta_sync_schedule.enabled ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.okta_sync[0].arn
}

resource "aws_cloudwatch_event_rule" "security_alerts" {
  count = local.enabled && var.security_alerts_schedule.enabled ? 1 : 0

  name                = "${module.this.id}-security-alerts"
  description         = "Scheduled trigger for GitHub security alerts monitoring"
  schedule_expression = var.security_alerts_schedule.schedule_expression
  tags                = module.this.tags
}

resource "aws_cloudwatch_event_target" "security_alerts" {
  count = local.enabled && var.security_alerts_schedule.enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_alerts[0].name
  target_id = "SecurityAlertsLambda"
  arn       = aws_lambda_function.this[0].arn

  input_transformer {
    input_paths = {
      source      = "$.source"
      detail_type = "$.detail-type"
      time        = "$.time"
      region      = "$.region"
    }
    input_template = <<-EOF
      {
        "version": "0",
        "source": <source>,
        "detail-type": <detail_type>,
        "time": <time>,
        "region": <region>,
        "detail": {"action": "security-alerts"}
      }
    EOF
  }
}

resource "aws_lambda_permission" "eventbridge_security_alerts" {
  count = local.enabled && var.security_alerts_schedule.enabled ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeSecurityAlerts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_alerts[0].arn
}

# ---------------------------------------------------------------------- iam ---

resource "aws_iam_role" "this" {
  count = local.enabled ? 1 : 0

  name        = module.this.id
  description = "IAM role for GitHub Ops App Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { "Service" : "lambda.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = module.this.tags
}

data "aws_iam_policy_document" "this" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:${local.aws_partition}:logs:${local.aws_region_name}:${local.aws_account_id}:log-group:/aws/lambda/${module.this.id}:*"]
  }

  dynamic "statement" {
    for_each = length(var.ssm_parameter_arns) > 0 ? [1] : []

    content {
      sid    = "SSMParameterAccess"
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = var.ssm_parameter_arns
    }
  }
}

resource "aws_iam_role_policy" "this" {
  count = local.enabled ? 1 : 0

  name   = module.this.id
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.this[0].json
}
