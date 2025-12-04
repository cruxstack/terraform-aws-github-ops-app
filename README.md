# terraform-aws-github-ops-app

Terraform module that deploys the [GitHub Ops App](https://github.com/cruxstack/github-ops-app) 
to AWS Lambda with API Gateway for webhook handling.

## Features

- **Okta Group Sync** - Automatically syncs Okta groups to GitHub teams based
  on configurable rules
- **Orphaned User Detection** - Identifies org members not in any synced Okta
  teams
- **PR Compliance Monitoring** - Detects when PRs bypass branch protection
  rules
- **Automatic Reconciliation** - Detects external team changes and triggers
  sync
- **Slack Notifications** - Rich messages for violations and sync reports

## Usage

```hcl
module "github_ops_app" {
  source = "github.com/cruxstack/terraform-aws-github-ops-app?ref=v1.0.0"

  name = "github-ops"

  # github app configuration (required)
  # webhook_secret is optional - if not provided, one will be auto-generated
  github_app_config = {
    app_id          = "123456"
    private_key     = var.github_app_private_key
    installation_id = "12345678"
    org             = "my-org"
  }

  # okta configuration (optional)
  okta_config = {
    enabled               = true
    domain                = "mycompany.okta.com"
    client_id             = var.okta_client_id
    private_key           = var.okta_private_key
    github_user_field     = "login"
    sync_safety_threshold = 0.5
    sync_rules = [
      {
        okta_group  = "engineering-team"
        github_team = "engineers"
      }
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
    monitored_branches = ["main", "master"]
  }

  # slack notifications (optional)
  slack_config = {
    enabled                = true
    token                  = var.slack_token
    channel                = "#github-ops"
    channel_pr_bypass      = "#security-alerts"      # optional: override for PR bypass alerts
    channel_okta_sync      = "#team-sync"            # optional: override for sync reports
    channel_orphaned_users = "#security-alerts"      # optional: override for orphaned user alerts
  }
}
```

## Quick Start

- **Create a GitHub App** with the required permissions 
  - [GitHub Ops App documentation](https://github.com/cruxstack/github-ops-app))
- **Deploy this module** with your GitHub App credentials
- **Configure the webhook URL** in your GitHub App settings using the
  `webhook_url` output
- **Optionally configure Okta** for team synchronization
- **Optionally configure Slack** for notifications

## Examples

- [Complete Example](examples/complete) - Full configuration with all features
  enabled

## Inputs

| Name                          | Description                                                                  | Type           | Default                                              | Required |
|-------------------------------|------------------------------------------------------------------------------|----------------|------------------------------------------------------|:--------:|
| `github_app_config`           | GitHub App configuration for authentication and webhook handling             | `object`       | n/a                                                  |   yes    |
| `bot_version`                 | Version of the GitHub Ops App to use (`latest` or specific tag like `v0.1.0`)| `string`       | `"latest"`                                           |    no    |
| `bot_repo`                    | GitHub repository URL for the GitHub Ops App source code                     | `string`       | `"https://github.com/cruxstack/github-ops-app.git"`  |    no    |
| `bot_force_rebuild_id`        | ID to force rebuilding the Lambda function source code                       | `string`       | `""`                                                 |    no    |
| `lambda_config`               | Configuration for the Lambda function                                        | `object`       | `{}`                                                 |    no    |
| `lambda_log_retention_days`   | Number of days to retain Lambda function logs                                | `number`       | `30`                                                 |    no    |
| `lambda_environment_variables`| Additional environment variables for the Lambda function                     | `map(string)`  | `{}`                                                 |    no    |
| `okta_config`                 | Okta configuration for user and group synchronization                        | `object`       | `{}`                                                 |    no    |
| `okta_sync_schedule`          | EventBridge schedule configuration for automatic Okta sync                   | `object`       | `{}`                                                 |    no    |
| `pr_compliance_config`        | Configuration for PR compliance monitoring                                   | `object`       | `{}`                                                 |    no    |
| `slack_config`                | Slack integration configuration for notifications                            | `object`       | `{}`                                                 |    no    |
| `api_gateway_config`          | Configuration for the API Gateway                                            | `object`       | `{}`                                                 |    no    |
| `ssm_parameter_arns`          | List of SSM Parameter Store ARNs for secrets retrieval                       | `list(string)` | `[]`                                                 |    no    |

### GitHub App Config

```hcl
github_app_config = {
  app_id          = string  # GitHub App ID
  private_key     = string  # GitHub App private key (PEM format)
  installation_id = string  # GitHub App installation ID
  org             = string  # GitHub organization name
  webhook_secret  = string  # (optional) GitHub webhook secret - auto-generated if not provided
}
```

### Okta Config

```hcl
okta_config = {
  enabled                      = bool         # Enable Okta integration (default: false)
  domain                       = string       # Okta domain (e.g., "mycompany.okta.com")
  client_id                    = string       # Okta OAuth client ID
  private_key                  = string       # Okta private key for OAuth
  key_id                       = string       # (optional) Okta private key ID
  github_user_field            = string       # Okta field containing GitHub username (default: "login")
  sync_rules                   = list(any)    # List of sync rules mapping Okta groups to GitHub teams
  sync_safety_threshold        = number       # Safety threshold to prevent mass removal (default: 0.5)
  orphaned_user_notifications  = bool         # Notify about users not in any synced team (default: true)
}
```

#### Sync Rules

Sync rules support both simple and pattern-based formats:

```hcl
# Simple format - direct mapping
sync_rules = [
  {
    okta_group  = "engineering-team"
    github_team = "engineers"
  }
]

# Pattern-based format - for multiple groups
sync_rules = [
  {
    name                   = "sync-engineering-teams"
    enabled                = true
    okta_group_pattern     = "^github-eng-.*"
    github_team_prefix     = "eng-"
    strip_prefix           = "github-eng-"
    sync_members           = true
    create_team_if_missing = true
  }
]
```

See the [GitHub Ops App documentation](https://github.com/cruxstack/github-ops-app/blob/main/docs/okta-setup.md#step-10-configure-sync-rules) for detailed sync rule configuration.

### Lambda Config

```hcl
lambda_config = {
  memory_size                    = number  # Memory in MB (default: 256)
  timeout                        = number  # Timeout in seconds (default: 30)
  runtime                        = string  # Lambda runtime (default: "provided.al2023")
  architecture                   = string  # CPU architecture (default: "x86_64")
  reserved_concurrent_executions = number  # Reserved concurrency (default: -1, unreserved)
}
```

### Slack Config

```hcl
slack_config = {
  enabled                = bool    # Enable Slack integration (default: false)
  token                  = string  # Slack bot token (xoxb-...)
  channel                = string  # Default Slack channel ID for notifications
  channel_pr_bypass      = string  # (optional) Channel for PR bypass alerts
  channel_okta_sync      = string  # (optional) Channel for sync reports
  channel_orphaned_users = string  # (optional) Channel for orphaned user alerts
}
```

Per-notification channels are optional and fall back to the default `channel` if not specified.

## Outputs

| Name                             | Description                                          |
|----------------------------------|------------------------------------------------------|
| `lambda_function_arn`            | ARN of the GitHub Ops App Lambda function            |
| `lambda_function_name`           | Name of the GitHub Ops App Lambda function           |
| `lambda_function_qualified_arn`  | Qualified ARN of the Lambda function                 |
| `lambda_function_invoke_arn`     | Invoke ARN of the Lambda function                    |
| `lambda_role_arn`                | ARN of the IAM role used by the Lambda function      |
| `lambda_role_name`               | Name of the IAM role used by the Lambda function     |
| `cloudwatch_log_group_name`      | Name of the CloudWatch Log Group                     |
| `cloudwatch_log_group_arn`       | ARN of the CloudWatch Log Group                      |
| `api_gateway_id`                 | ID of the API Gateway HTTP API                       |
| `api_gateway_arn`                | ARN of the API Gateway HTTP API                      |
| `api_gateway_endpoint`           | Base URL of the API Gateway                          |
| `api_gateway_execution_arn`      | Execution ARN of the API Gateway                     |
| `webhook_url`                    | Full webhook URL to configure in GitHub App settings |
| `webhook_secret`                 | Webhook secret to configure in GitHub App            |
| `eventbridge_rule_arn`           | ARN of the EventBridge rule for scheduled Okta sync  |
| `eventbridge_rule_name`          | Name of the EventBridge rule                         |

## Architecture

```
                                    +------------------+
                                    |   GitHub App     |
                                    +--------+---------+
                                             |
                                             | Webhooks
                                             v
+------------------+              +----------+---------+
|   EventBridge    |              |    API Gateway     |
|   (Scheduled)    |              |    HTTP API        |
+--------+---------+              +----------+---------+
         |                                   |
         |  /scheduled/okta-sync             |  /webhooks
         |                                   |
         +----------------+------------------+
                          |
                          v
               +----------+---------+
               |       Lambda       |
               |   GitHub Ops App   |
               +----------+---------+
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
   +------+------+ +------+------+ +------+------+
   |   GitHub    | |    Okta     | |    Slack    |
   |     API     | |     API     | |     API     |
   +-------------+ +-------------+ +-------------+
```

## Requirements

| Name      | Version |
|-----------|---------|
| terraform | >= 1.3  |
| aws       | >= 5.0  |

## License

MIT Licensed. See [LICENSE](LICENSE) for full details.
