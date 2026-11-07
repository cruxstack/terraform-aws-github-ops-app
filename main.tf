# =================================================================== locals ===

locals {
  enabled = module.this.enabled

  aws_account_id  = data.aws_caller_identity.current.account_id
  aws_region_name = data.aws_region.current.region
  aws_partition   = data.aws_partition.current.partition

  goarch = var.lambda_config.architecture == "arm64" ? "arm64" : "amd64"

  # the config objects are sensitive as a whole; these flags reveal nothing
  installer_enabled = var.installer_config.enabled
  okta_enabled      = nonsensitive(var.okta_config.enabled)
  slack_enabled     = nonsensitive(var.slack_config.enabled)
  admin_enabled     = nonsensitive(var.admin_token_config.enabled)
  store_secrets     = var.ssm_config.store_secrets

  generate_webhook_secret = !local.installer_enabled && nonsensitive(var.github_app_config.webhook_secret == "")
  generate_admin_token    = local.admin_enabled && nonsensitive(var.admin_token_config.token == "")

  # one() is null when the module is disabled and nothing is generated
  github_webhook_secret = local.installer_enabled ? "" : (local.generate_webhook_secret ? one(random_password.webhook_secret[*].result) : var.github_app_config.webhook_secret)
  admin_token           = local.admin_enabled ? (local.generate_admin_token ? one(random_password.admin_token[*].result) : var.admin_token_config.token) : ""

  ssm_parameter_prefix     = var.ssm_config.parameter_prefix != "" ? var.ssm_config.parameter_prefix : "/${module.this.id}/"
  ssm_parameter_arn_prefix = "arn:${local.aws_partition}:ssm:${local.aws_region_name}:${local.aws_account_id}:parameter${local.ssm_parameter_prefix}"

  # secrets passed to the function, as ssm parameters or plain variables; in
  # installer mode the installer saves the github app's own credentials
  provided_secrets = merge(
    local.installer_enabled ? {} : { APP_GITHUB_APP_PRIVATE_KEY = var.github_app_config.private_key },
    local.installer_enabled || local.generate_webhook_secret ? {} : { APP_GITHUB_WEBHOOK_SECRET = var.github_app_config.webhook_secret },
    local.okta_enabled ? { APP_OKTA_PRIVATE_KEY = var.okta_config.private_key } : {},
    local.slack_enabled ? { APP_SLACK_TOKEN = var.slack_config.token } : {},
    local.admin_enabled && !local.generate_admin_token ? { APP_ADMIN_TOKEN = var.admin_token_config.token } : {},
  )
  generated_secrets = merge(
    local.generate_webhook_secret ? { APP_GITHUB_WEBHOOK_SECRET = local.github_webhook_secret } : {},
    local.generate_admin_token ? { APP_ADMIN_TOKEN = local.admin_token } : {},
  )
  secrets      = merge(local.provided_secrets, local.generated_secrets)
  secret_names = nonsensitive(toset(keys(local.secrets)))
  # a secret given as an ssm parameter arn is passed as is, and its parameter
  # is readable; only whether it is an arn is revealed. generated secrets are
  # never arns, and are unknown until apply.
  secret_given_arns = {
    for name in nonsensitive(keys(local.provided_secrets)) : name => nonsensitive(local.provided_secrets[name])
    if nonsensitive(can(regex("^arn:aws[a-z-]*:ssm:", local.provided_secrets[name])))
  }
  stored_secret_names = local.store_secrets ? toset([
    for name in local.secret_names : name if !contains(keys(local.secret_given_arns), name)
  ]) : toset([])
  secret_environment = {
    for name in local.secret_names :
    name => contains(local.stored_secret_names, name) ? try(aws_ssm_parameter.secret[name].arn, null) : local.secrets[name]
  }
  readable_parameter_arns = distinct(concat(var.ssm_parameter_arns, values(local.secret_given_arns)))

  # the installer saves the credentials under the prefix, and the function
  # reads them from there once they exist
  github_credentials_environment = local.installer_enabled ? merge({
    GITHUB_APP_INSTALLER_ENABLED = "true"
    STORAGE_MODE                 = "aws-ssm"
    AWS_SSM_PARAMETER_PREFIX     = local.ssm_parameter_prefix
    APP_GITHUB_APP_ID            = "${local.ssm_parameter_arn_prefix}APP_GITHUB_APP_ID"
    APP_GITHUB_APP_PRIVATE_KEY   = "${local.ssm_parameter_arn_prefix}APP_GITHUB_APP_PRIVATE_KEY"
    APP_GITHUB_WEBHOOK_SECRET    = "${local.ssm_parameter_arn_prefix}APP_GITHUB_WEBHOOK_SECRET"
    }, var.ssm_config.kms_key_arn != "" ? { AWS_SSM_KMS_KEY_ID = var.ssm_config.kms_key_arn } : {}) : {
    APP_GITHUB_APP_ID = var.github_app_config.app_id
  }

  # with a named stage, api gateway passes paths with the stage prefix
  api_enabled = local.enabled && var.api_gateway_config.enabled
  base_path   = var.api_gateway_config.enabled && var.api_gateway_config.stage_name != "$default" ? "/${var.api_gateway_config.stage_name}" : ""
  public_url  = local.api_enabled ? "${one(aws_apigatewayv2_api.this[*].api_endpoint)}${local.base_path}" : ""

  # unset rule fields are left out, so the app applies its defaults
  okta_sync_rules = jsonencode([
    for rule in var.okta_config.sync_rules : { for k, v in rule : k => v if v != null }
  ])

  lambda_environment = merge(
    {
      APP_LOG_LEVEL               = var.log_level
      APP_GITHUB_ORG              = var.github_app_config.org
      APP_PR_COMPLIANCE_ENABLED   = tostring(var.pr_compliance_config.enabled)
      APP_SECURITY_ALERTS_ENABLED = tostring(var.security_alerts_config.enabled)
    },
    var.github_app_config.installation_id != "" ? { APP_GITHUB_INSTALLATION_ID = var.github_app_config.installation_id } : {},
    var.github_app_config.base_url != "" ? { APP_GITHUB_BASE_URL = var.github_app_config.base_url } : {},
    local.base_path != "" ? { APP_BASE_PATH = local.base_path } : {},
    local.public_url != "" ? { APP_PUBLIC_URL = local.public_url } : {},
    var.pr_compliance_config.enabled ? {
      APP_PR_MONITORED_BRANCHES = join(",", var.pr_compliance_config.monitored_branches)
    } : {},
    var.security_alerts_config.enabled ? {
      APP_SECURITY_ALERTS_MIN_AGE_DAYS = tostring(var.security_alerts_config.min_age_days)
      APP_SECURITY_ALERTS_MIN_SEVERITY = var.security_alerts_config.min_severity
    } : {},
    local.okta_enabled ? merge(
      {
        APP_OKTA_DOMAIN                      = var.okta_config.domain
        APP_OKTA_CLIENT_ID                   = var.okta_config.client_id
        APP_OKTA_GITHUB_USER_FIELD           = var.okta_config.github_user_field
        APP_OKTA_SYNC_RULES                  = local.okta_sync_rules
        APP_OKTA_SYNC_SAFETY_THRESHOLD       = tostring(var.okta_config.sync_safety_threshold)
        APP_OKTA_ORPHANED_USER_NOTIFICATIONS = tostring(var.okta_config.orphaned_user_notifications)
      },
      var.okta_config.private_key_id != "" ? { APP_OKTA_PRIVATE_KEY_ID = var.okta_config.private_key_id } : {},
      length(var.okta_config.scopes) > 0 ? { APP_OKTA_SCOPES = join(",", var.okta_config.scopes) } : {},
    ) : {},
    local.slack_enabled ? merge(
      { APP_SLACK_CHANNEL = var.slack_config.channel },
      var.slack_config.channel_pr_bypass != "" ? { APP_SLACK_CHANNEL_PR_BYPASS = var.slack_config.channel_pr_bypass } : {},
      var.slack_config.channel_okta_sync != "" ? { APP_SLACK_CHANNEL_OKTA_SYNC = var.slack_config.channel_okta_sync } : {},
      var.slack_config.channel_orphaned_users != "" ? { APP_SLACK_CHANNEL_ORPHANED_USERS = var.slack_config.channel_orphaned_users } : {},
      var.slack_config.channel_security_alerts != "" ? { APP_SLACK_CHANNEL_SECURITY_ALERTS = var.slack_config.channel_security_alerts } : {},
      var.pr_compliance_config.slack_footer_note != "" ? { APP_SLACK_FOOTER_NOTE_PR_BYPASS = var.pr_compliance_config.slack_footer_note } : {},
    ) : {},
    local.github_credentials_environment,
    local.secret_environment,
    var.lambda_environment_variables,
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ================================================================= secrets ===

resource "random_password" "webhook_secret" {
  count = local.enabled && local.generate_webhook_secret ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "admin_token" {
  count = local.enabled && local.generate_admin_token ? 1 : 0

  length  = 32
  special = false
}

resource "aws_ssm_parameter" "secret" {
  for_each = local.enabled ? local.stored_secret_names : toset([])

  name        = "${local.ssm_parameter_prefix}${each.key}"
  description = "${each.key} for ${module.this.id}"
  type        = "SecureString"
  value       = local.secrets[each.key]
  key_id      = var.ssm_config.kms_key_arn != "" ? var.ssm_config.kms_key_arn : null

  tags = module.this.tags
}

# ================================================================== lambda ===

# transitional: forget the pre-buildkit module.bot_artifact from state on
# upgrade, instead of trying to destroy its docker image
removed {
  from = module.bot_artifact

  lifecycle {
    destroy = false
  }
}

data "buildkit_context" "app" {
  count = local.enabled ? 1 : 0

  path = abspath("${path.module}/assets/lambda-function")
}

# github-ops-app built at app_version for the function's architecture
resource "buildkit_artifact" "app" {
  count = local.enabled ? 1 : 0

  build_context     = abspath("${path.module}/assets/lambda-function")
  dockerfile        = "Dockerfile"
  target            = "package"
  artifact_src_path = "/tmp/package.zip"
  artifact_src_type = "zip"
  artifact_dst_path = "${path.module}/dist/${module.this.id}/package.zip"

  build_args = {
    APP_VERSION = var.app_version
    APP_REPO    = var.app_repo
    GOARCH      = local.goarch
  }

  triggers = {
    context          = data.buildkit_context.app[0].digest
    app_version      = var.app_version
    app_repo         = var.app_repo
    goarch           = local.goarch
    force_rebuild_id = var.app_force_rebuild_id
  }
}

resource "aws_lambda_function" "this" {
  count = local.enabled ? 1 : 0

  function_name                  = module.this.id
  description                    = "GitHub Ops App: Okta group sync, PR compliance, and security alert reports"
  role                           = aws_iam_role.this[0].arn
  handler                        = "bootstrap"
  runtime                        = "provided.al2023"
  memory_size                    = var.lambda_config.memory_size
  timeout                        = var.lambda_config.timeout
  reserved_concurrent_executions = var.lambda_config.reserved_concurrent_executions
  architectures                  = [var.lambda_config.architecture]

  filename         = buildkit_artifact.app[0].artifact_path
  source_code_hash = buildkit_artifact.app[0].artifact_sha256

  environment {
    variables = local.lambda_environment
  }

  lifecycle {
    precondition {
      condition     = local.installer_enabled || nonsensitive(var.github_app_config.app_id != "" && var.github_app_config.private_key != "")
      error_message = "github_app_config.app_id and private_key are required unless installer_config.enabled is true."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.this,
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
  count = local.api_enabled ? 1 : 0

  name          = module.this.id
  protocol_type = "HTTP"
  description   = "GitHub Ops App webhooks and admin API"

  tags = module.this.tags
}

resource "aws_apigatewayv2_stage" "this" {
  count = local.api_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = var.api_gateway_config.stage_name
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_gateway_config.throttling_burst_limit
    throttling_rate_limit  = var.api_gateway_config.throttling_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      path              = "$context.path"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationStatus = "$context.integrationStatus"
      integrationError  = "$context.integrationErrorMessage"
    })
  }

  tags = module.this.tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = local.api_enabled ? 1 : 0

  name              = "/aws/apigateway/${module.this.id}"
  retention_in_days = var.lambda_log_retention_days
  tags              = module.this.tags
}

resource "aws_apigatewayv2_integration" "this" {
  count = local.api_enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  count = local.api_enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.this[0].id}"
}

resource "aws_lambda_permission" "api_gateway" {
  count = local.api_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}

# ============================================================= eventbridge ===

# each schedule sends an event whose detail names the scheduled action

resource "aws_cloudwatch_event_rule" "okta_sync" {
  count = local.enabled && var.okta_sync_schedule.enabled ? 1 : 0

  name                = "${module.this.id}-okta-sync"
  description         = "Scheduled Okta group sync of ${module.this.id}"
  schedule_expression = var.okta_sync_schedule.schedule_expression
  tags                = module.this.tags

  lifecycle {
    precondition {
      condition     = local.okta_enabled
      error_message = "okta_sync_schedule requires okta_config.enabled."
    }
  }
}

resource "aws_cloudwatch_event_target" "okta_sync" {
  count = local.enabled && var.okta_sync_schedule.enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.okta_sync[0].name
  target_id = "OktaSyncLambda"
  arn       = aws_lambda_function.this[0].arn

  input_transformer {
    input_paths = {
      id          = "$.id"
      source      = "$.source"
      detail_type = "$.detail-type"
      time        = "$.time"
      region      = "$.region"
    }
    input_template = <<-EOF
      {
        "version": "0",
        "id": <id>,
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
  description         = "Scheduled security alerts report of ${module.this.id}"
  schedule_expression = var.security_alerts_schedule.schedule_expression
  tags                = module.this.tags

  lifecycle {
    precondition {
      condition     = var.security_alerts_config.enabled
      error_message = "security_alerts_schedule requires security_alerts_config.enabled."
    }
  }
}

resource "aws_cloudwatch_event_target" "security_alerts" {
  count = local.enabled && var.security_alerts_schedule.enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_alerts[0].name
  target_id = "SecurityAlertsLambda"
  arn       = aws_lambda_function.this[0].arn

  input_transformer {
    input_paths = {
      id          = "$.id"
      source      = "$.source"
      detail_type = "$.detail-type"
      time        = "$.time"
      region      = "$.region"
    }
    input_template = <<-EOF
      {
        "version": "0",
        "id": <id>,
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

# --------------------------------------------------------------------- iam ---

resource "aws_iam_role" "this" {
  count = local.enabled ? 1 : 0

  name        = module.this.id
  description = "Role of the ${module.this.id} Lambda function"

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
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.lambda[0].arn}:*"]
  }

  dynamic "statement" {
    for_each = length(local.stored_secret_names) > 0 ? [1] : []

    content {
      sid       = "ReadSecrets"
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = [for name in local.stored_secret_names : aws_ssm_parameter.secret[name].arn]
    }
  }

  # the installer reads its status and saves the credentials under the prefix
  dynamic "statement" {
    for_each = local.installer_enabled ? [1] : []

    content {
      sid    = "InstallerCredentials"
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:PutParameter",
      ]
      resources = ["${local.ssm_parameter_arn_prefix}*"]
    }
  }

  dynamic "statement" {
    for_each = var.ssm_config.kms_key_arn != "" ? [1] : []

    content {
      sid       = "SecretsKey"
      effect    = "Allow"
      actions   = local.installer_enabled ? ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"] : ["kms:Decrypt"]
      resources = [var.ssm_config.kms_key_arn]
    }
  }

  dynamic "statement" {
    for_each = length(local.readable_parameter_arns) > 0 ? [1] : []

    content {
      sid       = "ReadParameters"
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = local.readable_parameter_arns
    }
  }
}

resource "aws_iam_role_policy" "this" {
  count = local.enabled ? 1 : 0

  name   = module.this.id
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.this[0].json
}
