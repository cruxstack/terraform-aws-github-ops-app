# ===================================================================== app ===

variable "app_version" {
  description = "Git tag, branch, or commit of github-ops-app to build. `latest` builds its default branch, which can include breaking changes."
  type        = string
  default     = "v1.0.0"

  validation {
    condition     = length(trimspace(var.app_version)) > 0
    error_message = "app_version must not be empty."
  }
}

variable "app_repo" {
  description = "Git URL of the github-ops-app source to build."
  type        = string
  default     = "https://github.com/cruxstack/github-ops-app.git"
}

variable "app_force_rebuild_id" {
  description = "Change this value to force a rebuild of the function's code."
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Log level of the function: `debug`, `info`, `warn`, or `error`."
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warn, error."
  }
}

# ------------------------------------------------------------------ lambda ---

variable "lambda_config" {
  description = "Configuration of the Lambda function. A full Okta sync can take minutes, so keep the timeout long."
  type = object({
    memory_size                    = optional(number, 256)
    timeout                        = optional(number, 600)
    architecture                   = optional(string, "arm64")
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

  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_config.architecture)
    error_message = "Lambda architecture must be arm64 or x86_64."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to keep the function's and API Gateway's logs in CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_days)
    error_message = "lambda_log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for the function. They override the module's."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------ github ---

variable "github_app_config" {
  description = "GitHub App the function runs as. `app_id` and `private_key` are required unless the installer is enabled. `installation_id` is looked up from the org when empty, and a `webhook_secret` is generated when empty. `base_url` is the API URL of a GitHub Enterprise Server."
  sensitive   = true
  type = object({
    org             = string
    app_id          = optional(string, "")
    private_key     = optional(string, "")
    installation_id = optional(string, "")
    webhook_secret  = optional(string, "")
    base_url        = optional(string, "")
  })

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_app_config.org))
    error_message = "github_app_config.org must be a GitHub organization name."
  }

  validation {
    condition     = can(regex("^[0-9]*$", var.github_app_config.app_id)) && can(regex("^[0-9]*$", var.github_app_config.installation_id))
    error_message = "github_app_config.app_id and installation_id must be numbers."
  }

  validation {
    condition     = var.github_app_config.webhook_secret == "" || length(var.github_app_config.webhook_secret) >= 16
    error_message = "github_app_config.webhook_secret must be at least 16 characters."
  }

  validation {
    condition     = var.github_app_config.base_url == "" || can(regex("^https?://[^/?#]+", var.github_app_config.base_url))
    error_message = "github_app_config.base_url must be an http(s) url, such as https://github.example.com/api/v3."
  }
}

variable "installer_config" {
  description = "GitHub App installer. When enabled, the function serves `/setup`, which creates the GitHub App from a manifest and saves its credentials to SSM under `ssm_config.parameter_prefix`; `github_app_config` then needs only `org`."
  type = object({
    enabled = optional(bool, false)
  })
  default = {}
}

# ---------------------------------------------------------------- secrets ---

variable "ssm_config" {
  description = "Where secrets are kept. With `store_secrets`, the module stores each secret it passes to the function as an SSM SecureString parameter under `parameter_prefix` (default `/<id>/`), and the function reads it at startup, so it doesn't appear in the function's configuration. The installer saves the GitHub App's credentials under the same prefix. `kms_key_arn` encrypts the parameters with a customer managed key instead of `aws/ssm`."
  type = object({
    store_secrets    = optional(bool, true)
    parameter_prefix = optional(string, "")
    kms_key_arn      = optional(string, "")
  })
  default = {}

  validation {
    condition     = var.ssm_config.parameter_prefix == "" || can(regex("^/([A-Za-z0-9_.-]+/)+$", var.ssm_config.parameter_prefix))
    error_message = "ssm_config.parameter_prefix must start and end with a slash, such as /github-ops-app/."
  }

  validation {
    condition     = var.ssm_config.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.ssm_config.kms_key_arn))
    error_message = "ssm_config.kms_key_arn must be a KMS key ARN."
  }
}

variable "ssm_parameter_arns" {
  description = "Other SSM parameter ARNs the function may read, for configuration values you set to a parameter ARN yourself."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------- admin ---

variable "admin_token_config" {
  description = "Admin token that protects the `/server/*` and `/scheduled/*` endpoints. A token is generated when none is given. When disabled, those endpoints are off; EventBridge schedules work either way."
  sensitive   = true
  type = object({
    enabled = optional(bool, true)
    token   = optional(string, "")
  })
  default = {}

  validation {
    condition     = var.admin_token_config.token == "" || length(var.admin_token_config.token) >= 16
    error_message = "admin_token_config.token must be at least 16 characters."
  }
}

# -------------------------------------------------------------------- okta ---

variable "okta_config" {
  description = "Okta group sync. `github_user_field` is the Okta profile attribute with each user's GitHub username. See the github-ops-app README for the sync rule fields."
  sensitive   = true
  type = object({
    enabled           = optional(bool, false)
    domain            = optional(string, "")
    client_id         = optional(string, "")
    private_key       = optional(string, "")
    private_key_id    = optional(string, "")
    scopes            = optional(list(string), [])
    github_user_field = optional(string, "githubUsername")
    sync_rules = optional(list(object({
      name                   = optional(string)
      enabled                = optional(bool)
      okta_group_name        = optional(string)
      okta_group_pattern     = optional(string)
      github_team_name       = optional(string)
      github_team_prefix     = optional(string)
      strip_prefix           = optional(string)
      sync_members           = optional(bool)
      create_team_if_missing = optional(bool)
      team_privacy           = optional(string)
    })), [])
    sync_safety_threshold       = optional(number, 0.5)
    orphaned_user_notifications = optional(bool, true)
  })
  default = {}

  validation {
    condition     = !var.okta_config.enabled || (var.okta_config.domain != "" && var.okta_config.client_id != "" && var.okta_config.private_key != "" && length(var.okta_config.sync_rules) > 0)
    error_message = "When Okta is enabled, domain, client_id, private_key, and at least one sync rule are required."
  }

  validation {
    condition     = var.okta_config.domain == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$", var.okta_config.domain))
    error_message = "okta_config.domain must be a host name, such as example.okta.com, without https://."
  }

  validation {
    condition = alltrue([
      for r in var.okta_config.sync_rules :
      (r.okta_group_name == null ? "" : r.okta_group_name) != "" ? (r.okta_group_pattern == null ? "" : r.okta_group_pattern) == "" : (r.okta_group_pattern == null ? "" : r.okta_group_pattern) != ""
    ])
    error_message = "Each Okta sync rule must set exactly one of okta_group_name and okta_group_pattern."
  }

  validation {
    condition = alltrue([
      for r in var.okta_config.sync_rules :
      (r.okta_group_pattern == null ? "" : r.okta_group_pattern) == "" || (r.github_team_name == null ? "" : r.github_team_name) == ""
    ])
    error_message = "An Okta sync rule with okta_group_pattern can't set github_team_name; use github_team_prefix and strip_prefix."
  }

  validation {
    condition     = alltrue([for r in var.okta_config.sync_rules : contains(["", "closed", "secret"], r.team_privacy == null ? "" : r.team_privacy)])
    error_message = "Okta sync rule team_privacy must be closed or secret."
  }

  validation {
    condition     = var.okta_config.sync_safety_threshold >= 0 && var.okta_config.sync_safety_threshold <= 1
    error_message = "okta_config.sync_safety_threshold must be between 0 and 1."
  }
}

variable "okta_sync_schedule" {
  description = "EventBridge schedule for the Okta sync."
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

# --------------------------------------------------------- security alerts ---

variable "security_alerts_config" {
  description = "Reports of open Dependabot, code scanning, and secret scanning alerts older than `min_age_days` at or above `min_severity`."
  type = object({
    enabled      = optional(bool, false)
    min_age_days = optional(number, 30)
    min_severity = optional(string, "high")
  })
  default = {}

  validation {
    condition     = var.security_alerts_config.min_age_days >= 0 && floor(var.security_alerts_config.min_age_days) == var.security_alerts_config.min_age_days
    error_message = "security_alerts_config.min_age_days must be a whole number of 0 or more."
  }

  validation {
    condition     = contains(["critical", "high", "medium", "low"], var.security_alerts_config.min_severity)
    error_message = "security_alerts_config.min_severity must be one of: critical, high, medium, low."
  }
}

variable "security_alerts_schedule" {
  description = "EventBridge schedule for the security alerts report."
  type = object({
    enabled             = optional(bool, false)
    schedule_expression = optional(string, "rate(24 hours)")
  })
  default = {}

  validation {
    condition     = !var.security_alerts_schedule.enabled || can(regex("^(rate|cron)\\(", var.security_alerts_schedule.schedule_expression))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

# ----------------------------------------------------------- pr compliance ---

variable "pr_compliance_config" {
  description = "Reports of PRs merged into `monitored_branches` (names or globs, such as `release/*`) without meeting their branch's requirements. `slack_footer_note` is Slack mrkdwn added to each report."
  type = object({
    enabled            = optional(bool, false)
    monitored_branches = optional(list(string), ["main", "master"])
    slack_footer_note  = optional(string, "")
  })
  default = {}

  validation {
    condition     = !var.pr_compliance_config.enabled || length(var.pr_compliance_config.monitored_branches) > 0
    error_message = "pr_compliance_config.monitored_branches must not be empty."
  }
}

# ------------------------------------------------------------------- slack ---

variable "slack_config" {
  description = "Slack notifications. Each `channel_*` overrides `channel` for one report."
  sensitive   = true
  type = object({
    enabled                 = optional(bool, false)
    token                   = optional(string, "")
    channel                 = optional(string, "")
    channel_pr_bypass       = optional(string, "")
    channel_okta_sync       = optional(string, "")
    channel_orphaned_users  = optional(string, "")
    channel_security_alerts = optional(string, "")
  })
  default = {}

  validation {
    condition     = !var.slack_config.enabled || (var.slack_config.token != "" && var.slack_config.channel != "")
    error_message = "When Slack is enabled, both token and channel must be specified."
  }
}

# ------------------------------------------------------------- api gateway ---

variable "api_gateway_config" {
  description = "HTTP API that receives GitHub webhooks. With a `stage_name` other than `$default`, every route is under `/<stage_name>`. Requests above the throttling limits get `429`."
  type = object({
    enabled                = optional(bool, true)
    stage_name             = optional(string, "v1")
    throttling_burst_limit = optional(number, 100)
    throttling_rate_limit  = optional(number, 50)
  })
  default = {}

  validation {
    condition     = var.api_gateway_config.stage_name == "$default" || can(regex("^[A-Za-z0-9_-]{1,128}$", var.api_gateway_config.stage_name))
    error_message = "api_gateway_config.stage_name must be $default or letters, numbers, hyphens, and underscores."
  }

  validation {
    condition     = var.api_gateway_config.throttling_burst_limit >= 0 && var.api_gateway_config.throttling_rate_limit >= 0
    error_message = "API Gateway throttling limits must not be negative."
  }
}
