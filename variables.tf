# ================================================================== general ===

variable "bot_version" {
  description = "Version of the GitHub Ops App to use. Use 'latest' for the main branch or a specific version tag like 'v0.1.0'."
  type        = string
  default     = "latest"
}

variable "bot_repo" {
  description = "GitHub repository URL for the GitHub Ops App source code."
  type        = string
  default     = "https://github.com/cruxstack/github-ops-app.git"
}

variable "bot_force_rebuild_id" {
  description = "ID to force rebuilding the Lambda function source code. Increment this value to trigger a rebuild."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------- lambda ---

variable "lambda_config" {
  description = "Configuration for the GitHub Ops App Lambda function."
  type = object({
    memory_size                    = optional(number, 256)
    timeout                        = optional(number, 30)
    runtime                        = optional(string, "provided.al2023")
    architecture                   = optional(string, "x86_64")
    reserved_concurrent_executions = optional(number, -1)
  })
  default = {}

  validation {
    condition     = var.lambda_config.memory_size >= 128 && var.lambda_config.memory_size <= 10240
    error_message = "Lambda memory_size must be between 128 and 10240 MB."
  }

  validation {
    condition     = var.lambda_config.timeout >= 1 && var.lambda_config.timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs in CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.lambda_log_retention_days)
    error_message = "Lambda log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for the Lambda function."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------- github ---

variable "github_app_config" {
  description = "GitHub App configuration for authentication and webhook handling. If webhook_secret is not provided, one will be automatically generated."
  sensitive   = true
  type = object({
    app_id          = string
    private_key     = string
    installation_id = string
    org             = string
    webhook_secret  = optional(string, "")
  })

  validation {
    condition     = var.github_app_config.app_id != ""
    error_message = "GitHub App ID is required."
  }

  validation {
    condition     = var.github_app_config.private_key != ""
    error_message = "GitHub App private key is required."
  }

  validation {
    condition     = var.github_app_config.installation_id != ""
    error_message = "GitHub App installation ID is required."
  }

  validation {
    condition     = var.github_app_config.org != ""
    error_message = "GitHub organization name is required."
  }
}

# --------------------------------------------------------------------- okta ---

variable "okta_config" {
  description = "Okta configuration for user and group synchronization with GitHub teams."
  sensitive   = true
  type = object({
    enabled                     = optional(bool, false)
    domain                      = optional(string, "")
    client_id                   = optional(string, "")
    private_key                 = optional(string, "")
    key_id                      = optional(string, "")
    github_user_field           = optional(string, "login")
    sync_rules                  = optional(list(any), [])
    sync_safety_threshold       = optional(number, 0.5)
    orphaned_user_notifications = optional(bool, true)
  })
  default = {}

  validation {
    condition     = !var.okta_config.enabled || (var.okta_config.domain != "" && var.okta_config.client_id != "" && var.okta_config.private_key != "")
    error_message = "When Okta is enabled, domain, client_id, and private_key must all be specified."
  }

  validation {
    condition     = var.okta_config.sync_safety_threshold >= 0 && var.okta_config.sync_safety_threshold <= 1
    error_message = "Okta sync safety threshold must be between 0 and 1."
  }
}

variable "okta_sync_schedule" {
  description = "EventBridge schedule configuration for automatic Okta-GitHub team synchronization."
  type = object({
    enabled             = optional(bool, false)
    schedule_expression = optional(string, "rate(1 hour)")
  })
  default = {}

  validation {
    condition     = !var.okta_sync_schedule.enabled || can(regex("^(rate|cron)\\(", var.okta_sync_schedule.schedule_expression))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

# ----------------------------------------------------------- pr compliance ---

variable "pr_compliance_config" {
  description = "Configuration for PR compliance monitoring to detect branch protection bypasses."
  type = object({
    enabled            = optional(bool, false)
    monitored_branches = optional(list(string), ["main", "master"])
    slack_footer_note  = optional(string, "")
  })
  default = {}
}

# -------------------------------------------------------------------- slack ---

variable "slack_config" {
  description = "Slack integration configuration for sending notifications."
  sensitive   = true
  type = object({
    enabled                = optional(bool, false)
    token                  = optional(string, "")
    channel                = optional(string, "")
    channel_pr_bypass      = optional(string, "")
    channel_okta_sync      = optional(string, "")
    channel_orphaned_users = optional(string, "")
  })
  default = {}

  validation {
    condition     = !var.slack_config.enabled || (var.slack_config.token != "" && var.slack_config.channel != "")
    error_message = "When Slack is enabled, both token and channel must be specified."
  }
}

# -------------------------------------------------------------- api gateway ---

variable "api_gateway_config" {
  description = "Configuration for the API Gateway that exposes webhook endpoints."
  type = object({
    enabled            = optional(bool, true)
    stage_name         = optional(string, "v1")
    cors_allow_origins = optional(list(string), ["*"])
  })
  default = {}
}

# --------------------------------------------------------------------- ssm ---

variable "ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs that the Lambda function should have access to for secrets retrieval."
  type        = list(string)
  default     = []
}
