provider "aws" {
  region = "us-east-1"
}

module "github_ops_app" {
  source = "../../"

  # naming context
  namespace   = "eg"
  environment = "ue1"
  stage       = "prod"
  name        = "github-ops"

  # github-ops-app release to build
  app_version = "v1.0.0"

  # github app (required); the installation is looked up from the org, and a
  # webhook secret is generated when none is given
  github_app_config = {
    org         = var.github_org
    app_id      = var.github_app_id
    private_key = var.github_app_private_key
  }

  # or let the function create the github app: leave out app_id and
  # private_key, enable the installer, and visit the setup_url output
  # installer_config = { enabled = true }

  # okta group sync (optional)
  okta_config = {
    enabled           = true
    domain            = var.okta_domain
    client_id         = var.okta_client_id
    private_key       = var.okta_private_key
    private_key_id    = var.okta_private_key_id
    github_user_field = "githubUsername"
    sync_rules = [
      # one okta group to one team
      {
        name                   = "platform"
        okta_group_name        = "Platform Engineers"
        github_team_name       = "platform"
        create_team_if_missing = true
      },
      # every okta group named github-eng-* to a team named eng-*
      {
        name                   = "engineering-teams"
        okta_group_pattern     = "^github-eng-"
        strip_prefix           = "github-eng-"
        github_team_prefix     = "eng-"
        create_team_if_missing = true
      },
    ]
  }

  okta_sync_schedule = {
    enabled             = true
    schedule_expression = "rate(1 hour)"
  }

  # pr compliance monitoring
  pr_compliance_config = {
    enabled            = true
    monitored_branches = ["main", "master", "release/*"]
    slack_footer_note  = "_Please review the <https://example.com/policy|branch protection policy>._"
  }

  # stale security alerts
  security_alerts_config = {
    enabled      = true
    min_age_days = 30
    min_severity = "high"
  }

  security_alerts_schedule = {
    enabled             = true
    schedule_expression = "cron(0 13 ? * MON *)"
  }

  # slack notifications (optional)
  slack_config = {
    enabled                 = true
    token                   = var.slack_token
    channel                 = var.slack_channel
    channel_security_alerts = var.slack_channel_security_alerts
  }

  lambda_config = {
    architecture = "arm64"
    timeout      = 600
  }

  api_gateway_config = {
    stage_name = "$default"
  }
}

# ---------------------------------------------------------------- variables ---

variable "github_org" {
  type        = string
  description = "GitHub organization name"
}

variable "github_app_id" {
  type        = string
  description = "GitHub App ID"
}

variable "github_app_private_key" {
  type        = string
  sensitive   = true
  description = "GitHub App private key (PEM)"
}

variable "okta_domain" {
  type        = string
  description = "Okta domain, such as example.okta.com"
}

variable "okta_client_id" {
  type        = string
  description = "Okta OAuth client ID"
}

variable "okta_private_key" {
  type        = string
  sensitive   = true
  description = "Okta OAuth private key (PEM)"
}

variable "okta_private_key_id" {
  type        = string
  description = "Okta OAuth key ID (kid), if the app has more than one key"
  default     = ""
}

variable "slack_token" {
  type        = string
  sensitive   = true
  description = "Slack bot token"
}

variable "slack_channel" {
  type        = string
  description = "Slack channel ID for notifications"
}

variable "slack_channel_security_alerts" {
  type        = string
  description = "Slack channel ID for security alert reports; falls back to slack_channel"
  default     = ""
}

# ------------------------------------------------------------------ outputs ---

output "webhook_url" {
  description = "Webhook URL to set in the GitHub App's settings"
  value       = module.github_ops_app.webhook_url
}

output "webhook_secret" {
  description = "Webhook secret to set in the GitHub App's settings"
  value       = module.github_ops_app.webhook_secret
  sensitive   = true
}

output "admin_token" {
  description = "Admin token for the /server/* and /scheduled/* endpoints"
  value       = module.github_ops_app.admin_token
  sensitive   = true
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.github_ops_app.lambda_function_name
}
