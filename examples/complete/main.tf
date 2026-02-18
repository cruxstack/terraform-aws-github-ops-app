provider "aws" {
  region = "us-east-1"
}

module "github_ops_app" {
  source = "../../"

  # naming context
  namespace   = "eg"
  environment = "uw2"
  stage       = "prod"
  name        = "github-ops"

  # bot configuration
  bot_version = "latest" # or use a specific version like "v0.1.0"

  # github app configuration (required)
  # webhook_secret is optional - if not provided, one will be generated
  github_app_config = {
    app_id          = var.github_app_id
    private_key     = var.github_app_private_key
    installation_id = var.github_app_installation_id
    org             = var.github_org
    # webhook_secret = var.github_webhook_secret  # optional - auto-generated if omitted
  }

  # okta configuration (optional)
  okta_config = {
    enabled                     = true
    domain                      = var.okta_domain
    client_id                   = var.okta_client_id
    private_key                 = var.okta_private_key
    key_id                      = var.okta_key_id # optional
    github_user_field           = "login"
    sync_safety_threshold       = 0.5
    orphaned_user_notifications = true
    sync_rules = [
      # simple format - direct mapping
      {
        okta_group  = "engineering-team"
        github_team = "engineers"
      },
      {
        okta_group  = "platform-team"
        github_team = "platform"
      },
      # pattern-based format - for multiple groups
      # {
      #   name                   = "sync-all-github-teams"
      #   enabled                = true
      #   okta_group_pattern     = "^github-.*"
      #   github_team_prefix     = ""
      #   strip_prefix           = "github-"
      #   sync_members           = true
      #   create_team_if_missing = true
      # }
    ]
  }

  # schedule okta sync every hour
  okta_sync_schedule = {
    enabled             = true
    schedule_expression = "rate(1 hour)"
  }

  # pr compliance monitoring
  pr_compliance_config = {
    enabled            = true
    monitored_branches = ["main", "master", "release/*"]
  }

  # security alerts monitoring
  security_alerts_config = {
    enabled      = true
    min_age_days = 30     # only report alerts older than 30 days
    min_severity = "high" # minimum severity: critical, high, medium, low
  }

  # schedule security alerts check daily
  security_alerts_schedule = {
    enabled             = true
    schedule_expression = "rate(24 hours)"
  }

  # slack notifications (optional)
  slack_config = {
    enabled                 = true
    token                   = var.slack_token
    channel                 = var.slack_channel
    channel_pr_bypass       = var.slack_channel_pr_bypass       # optional: override for PR bypass alerts
    channel_okta_sync       = var.slack_channel_okta_sync       # optional: override for sync reports
    channel_orphaned_users  = var.slack_channel_orphaned_users  # optional: override for orphaned user alerts
    channel_security_alerts = var.slack_channel_security_alerts # optional: override for security alerts
  }

  # lambda configuration
  lambda_config = {
    memory_size  = 256
    timeout      = 30
    architecture = "x86_64"
  }

  lambda_log_retention_days = 30

  # api gateway configuration
  api_gateway_config = {
    enabled            = true
    stage_name         = "$default"
    cors_allow_origins = ["*"]
  }
}

# -----------------------------------------------------------------------------
# variables
# -----------------------------------------------------------------------------

variable "github_app_id" {
  type        = string
  description = "GitHub App ID"
}

variable "github_app_private_key" {
  type        = string
  sensitive   = true
  description = "GitHub App private key (PEM format)"
}

variable "github_app_installation_id" {
  type        = string
  description = "GitHub App installation ID"
}

variable "github_org" {
  type        = string
  description = "GitHub organization name"
}

variable "github_webhook_secret" {
  type        = string
  sensitive   = true
  description = "GitHub webhook secret (optional - auto-generated if not provided)"
  default     = ""
}

variable "okta_domain" {
  type        = string
  description = "Okta domain (e.g., 'mycompany.okta.com')"
  default     = ""
}

variable "okta_client_id" {
  type        = string
  description = "Okta OAuth client ID"
  default     = ""
}

variable "okta_private_key" {
  type        = string
  sensitive   = true
  description = "Okta private key for OAuth"
  default     = ""
}

variable "okta_key_id" {
  type        = string
  description = "Okta private key ID (optional)"
  default     = ""
}

variable "slack_token" {
  type        = string
  sensitive   = true
  description = "Slack bot token"
  default     = ""
}

variable "slack_channel" {
  type        = string
  description = "Slack channel ID for notifications"
  default     = ""
}

variable "slack_channel_pr_bypass" {
  type        = string
  description = "Slack channel ID for PR bypass alerts (optional, falls back to slack_channel)"
  default     = ""
}

variable "slack_channel_okta_sync" {
  type        = string
  description = "Slack channel ID for Okta sync reports (optional, falls back to slack_channel)"
  default     = ""
}

variable "slack_channel_orphaned_users" {
  type        = string
  description = "Slack channel ID for orphaned user alerts (optional, falls back to slack_channel)"
  default     = ""
}

variable "slack_channel_security_alerts" {
  type        = string
  description = "Slack channel ID for security alerts (optional, falls back to slack_channel)"
  default     = ""
}

# -----------------------------------------------------------------------------
# outputs
# -----------------------------------------------------------------------------

output "lambda_function_arn" {
  description = "ARN of the GitHub Ops App Lambda function"
  value       = module.github_ops_app.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the GitHub Ops App Lambda function"
  value       = module.github_ops_app.lambda_function_name
}

output "webhook_url" {
  description = "Webhook URL to configure in GitHub App settings"
  value       = module.github_ops_app.webhook_url
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.github_ops_app.api_gateway_endpoint
}

output "webhook_secret" {
  description = "Webhook secret to configure in GitHub App settings"
  value       = module.github_ops_app.webhook_secret
  sensitive   = true
}
