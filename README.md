# terraform-aws-github-ops-app

Terraform module that deploys
[github-ops-app](https://github.com/cruxstack/github-ops-app) to AWS Lambda,
with an API Gateway HTTP API for GitHub webhooks and EventBridge schedules for
its periodic jobs.

## Features

- **Okta group sync** - Sync Okta group members to GitHub teams on a schedule
  and after someone changes a team outside Okta
- **PR compliance monitoring** - Report PRs merged without the reviews and
  status checks their branch requires
- **Security alerts monitoring** - Report stale Dependabot, code scanning, and
  secret scanning alerts
- **GitHub App installer** - Optionally create the GitHub App from the
  function, with its credentials saved to SSM
- **Secrets in SSM** - Secrets are SecureString parameters the function reads
  at startup, not values in its configuration
- **Slack notifications** - Reports for each feature, in per-feature channels

## Requirements

| Name      | Version     |
| --------- | ----------- |
| terraform | `>= 1.7`    |
| aws       | `>= 6.72.0` |
| buildkit  | `>= 0.0.2`  |
| random    | `>= 3.9.1`  |

The module builds the function from source with the
[cruxstack/buildkit](https://registry.terraform.io/providers/cruxstack/buildkit)
provider, which needs a BuildKit endpoint where Terraform runs: Docker Desktop,
OrbStack, or Colima, `BUILDKIT_HOST`, or an embedded rootless `buildkitd` on
Linux.

## Usage

```hcl
module "github_ops_app" {
  source = "github.com/cruxstack/terraform-aws-github-ops-app?ref=v1.0.0"

  name = "github-ops"

  github_app_config = {
    org         = "acme"
    app_id      = "123456"
    private_key = var.github_app_private_key
  }

  okta_config = {
    enabled     = true
    domain      = "acme.okta.com"
    client_id   = var.okta_client_id
    private_key = var.okta_private_key
    sync_rules = [
      {
        okta_group_pattern     = "^github-eng-"
        strip_prefix           = "github-eng-"
        github_team_prefix     = "eng-"
        create_team_if_missing = true
      },
    ]
  }

  okta_sync_schedule = {
    enabled = true
  }

  pr_compliance_config = {
    enabled            = true
    monitored_branches = ["main", "release/*"]
  }

  slack_config = {
    enabled = true
    token   = var.slack_token
    channel = "C01234ABCDE"
  }
}
```

Then set the GitHub App's webhook URL and secret to the `webhook_url` and
`webhook_secret` outputs. The app needs the permissions listed in
[github-ops-app's setup guide](https://github.com/cruxstack/github-ops-app/blob/main/docs/github-app-setup.md#permissions).

See [examples/complete](examples/complete) for every feature.

### GitHub App Installer

Leave out the GitHub App's credentials and enable the installer to create the
app from the function:

```hcl
module "github_ops_app" {
  source = "github.com/cruxstack/terraform-aws-github-ops-app?ref=v1.0.0"

  name = "github-ops"

  github_app_config = { org = "acme" }
  installer_config  = { enabled = true }
}
```

1. Apply, and open the `setup_url` output.
2. Create the app; the installer fills in the webhook URL, and GitHub asks you
   to confirm.
3. Install the app on the organization from the success page.

The installer saves the app's credentials as SSM parameters under the
`ssm_parameter_prefix` output, and the next invocation reads them. Once an app
is registered, the function refuses new installer codes. Afterwards, set
`installer_config.enabled = false`; the function keeps reading the saved
credentials. Terraform doesn't manage the parameters the installer creates, so
`terraform destroy` leaves them.

### Secrets

Each secret the module passes to the function (the GitHub App private key,
webhook secret, Okta private key, Slack token, and admin token) is a
SecureString parameter under `ssm_config.parameter_prefix`, and the function
gets the parameter's ARN, so the value doesn't appear in the function's
configuration. The function's role can read only those parameters. Set
`ssm_config.store_secrets = false` to pass them as plain environment variables
instead.

To keep a secret out of Terraform, set it to the ARN of a parameter you
manage. The module passes the ARN as is and lets the function read that
parameter:

```hcl
  slack_config = {
    enabled = true
    token   = "arn:aws:ssm:us-east-1:111122223333:parameter/slack/token"
    channel = "C01234ABCDE"
  }
```

## Inputs

In addition to the variables documented below, this module includes several
other optional variables (e.g., `name`, `tags`, etc.) provided by the
`cloudposse/label/null` module. Please refer to its [documentation](https://registry.terraform.io/modules/cloudposse/label/null/latest)
for more details on these variables.

| Name                           | Description                                                                                             | Type           | Default                                             | Required |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- | -------------- | --------------------------------------------------- | -------- |
| `github_app_config`            | GitHub App: `org`, `app_id`, `private_key`, `installation_id`, `webhook_secret`, `base_url` (sensitive) | `object`       | n/a                                                 | yes      |
| `app_version`                  | git tag, branch, or commit of github-ops-app to build; `latest` builds its default branch               | `string`       | `"v1.0.0"`                                          | no       |
| `app_repo`                     | git URL of the github-ops-app source                                                                    | `string`       | `"https://github.com/cruxstack/github-ops-app.git"` | no       |
| `app_force_rebuild_id`         | change to force a rebuild of the function's code                                                        | `string`       | `""`                                                | no       |
| `log_level`                    | `debug`, `info`, `warn`, or `error`                                                                     | `string`       | `"info"`                                            | no       |
| `installer_config`             | `enabled`: serve the GitHub App installer at `/setup`                                                   | `object`       | `{}`                                                | no       |
| `ssm_config`                   | `store_secrets`, `parameter_prefix` (default `/<id>/`), `kms_key_arn`                                   | `object`       | `{}`                                                | no       |
| `ssm_parameter_arns`           | other parameter ARNs the function may read                                                              | `list(string)` | `[]`                                                | no       |
| `admin_token_config`           | `enabled`, `token` (generated if empty, at least 16 characters) (sensitive)                             | `object`       | `{}`                                                | no       |
| `okta_config`                  | Okta group sync; see [below](#okta-sync-rules) (sensitive)                                              | `object`       | `{}`                                                | no       |
| `okta_sync_schedule`           | `enabled`, `schedule_expression` (default `rate(1 hour)`)                                               | `object`       | `{}`                                                | no       |
| `pr_compliance_config`         | `enabled`, `monitored_branches` (names or globs), `slack_footer_note`                                   | `object`       | `{}`                                                | no       |
| `security_alerts_config`       | `enabled`, `min_age_days` (default `30`), `min_severity` (default `high`)                               | `object`       | `{}`                                                | no       |
| `security_alerts_schedule`     | `enabled`, `schedule_expression` (default `rate(24 hours)`)                                             | `object`       | `{}`                                                | no       |
| `slack_config`                 | `enabled`, `token`, `channel`, and `channel_*` overrides per report (sensitive)                         | `object`       | `{}`                                                | no       |
| `api_gateway_config`           | `enabled`, `stage_name` (default `v1`), `throttling_burst_limit`, `throttling_rate_limit`               | `object`       | `{}`                                                | no       |
| `lambda_config`                | `memory_size` (256), `timeout` (600), `architecture` (`arm64`), `reserved_concurrent_executions`        | `object`       | `{}`                                                | no       |
| `lambda_log_retention_days`    | days to keep the function's and API's logs                                                              | `number`       | `30`                                                | no       |
| `lambda_environment_variables` | more environment variables for the function; they override the module's                                 | `map(string)`  | `{}`                                                | no       |

### Okta Sync Rules

`okta_config` takes the domain, `client_id`, `private_key`, optional
`private_key_id` and `scopes`, `github_user_field` (default `githubUsername`),
`sync_safety_threshold` (default `0.5`), `orphaned_user_notifications`
(default `true`), and `sync_rules`. Each rule sets exactly one of
`okta_group_name` and `okta_group_pattern`:

```hcl
sync_rules = [
  {
    name                   = "platform"
    okta_group_name        = "Platform Engineers"
    github_team_name       = "platform"
    create_team_if_missing = true
  },
  {
    name               = "engineering-teams"
    okta_group_pattern = "^github-eng-"
    strip_prefix       = "github-eng-"
    github_team_prefix = "eng-"
    team_privacy       = "secret"
  },
]
```

The other fields are `enabled`, `sync_members`, and `create_team_if_missing`,
which defaults to `false`: a missing team is reported instead of created. See
[github-ops-app's sync rules](https://github.com/cruxstack/github-ops-app#okta-sync-rules)
for what each does.

## Outputs

| Name                                    | Description                                                                  |
| --------------------------------------- | ---------------------------------------------------------------------------- |
| `webhook_url`                           | webhook URL to set in the GitHub App's settings                              |
| `webhook_secret`                        | webhook secret to set in the GitHub App (sensitive); null with the installer |
| `setup_url`                             | URL of the GitHub App installer, when enabled                                |
| `public_url`                            | base URL of the app's routes, including the stage                            |
| `admin_token`                           | token for the `/server/*` and `/scheduled/*` endpoints (sensitive)           |
| `ssm_parameter_prefix`                  | SSM path of the secrets and the installer's credentials                      |
| `ssm_parameter_arns`                    | ARNs of the secret parameters the module manages, by name                    |
| `lambda_function_arn`                   | ARN of the Lambda function                                                   |
| `lambda_function_name`                  | name of the Lambda function                                                  |
| `lambda_function_qualified_arn`         | qualified ARN of the Lambda function                                         |
| `lambda_function_invoke_arn`            | invoke ARN of the Lambda function                                            |
| `lambda_role_arn`                       | ARN of the function's IAM role                                               |
| `lambda_role_name`                      | name of the function's IAM role                                              |
| `cloudwatch_log_group_name`             | name of the function's log group                                             |
| `cloudwatch_log_group_arn`              | ARN of the function's log group                                              |
| `api_gateway_id`                        | ID of the HTTP API                                                           |
| `api_gateway_arn`                       | ARN of the HTTP API                                                          |
| `api_gateway_endpoint`                  | base URL of the HTTP API, without the stage                                  |
| `api_gateway_execution_arn`             | execution ARN of the HTTP API                                                |
| `eventbridge_rule_arn`                  | ARN of the Okta sync schedule, if enabled                                    |
| `eventbridge_rule_name`                 | name of the Okta sync schedule, if enabled                                   |
| `eventbridge_security_alerts_rule_arn`  | ARN of the security alerts schedule, if enabled                              |
| `eventbridge_security_alerts_rule_name` | name of the security alerts schedule, if enabled                             |

## Architecture

```
                                    +------------------+
                                    |   GitHub App     |
                                    +--------+---------+
                                             |
                                             | webhooks
                                             v
+------------------+              +----------+---------+     +-------------+
|   EventBridge    |              |    API Gateway     |     |     SSM     |
|   schedules      |              |    HTTP API        |     |   secrets   |
+--------+---------+              +----------+---------+     +------+------+
         |                                   |                      |
         |  {"action": "okta-sync"}          |  /webhooks           |
         |                                   |                      |
         +----------------+------------------+                      |
                          |                                         |
                          v                                         |
               +----------+---------+                               |
               |       Lambda       | <-----------------------------+
               |   github-ops-app   |
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

## Upgrading to v1

v1 runs [github-ops-app v1](https://github.com/cruxstack/github-ops-app/blob/main/docs/upgrading-to-v1.md),
which validates its configuration at startup, requires signed webhooks, and
needs two more GitHub App permissions; read its upgrade guide too.

| v0                                                | v1                                                              |
| ------------------------------------------------- | --------------------------------------------------------------- |
| `bot_version` (default `latest`)                  | `app_version` (pinned to `v1.0.0`)                              |
| `bot_repo`                                        | `app_repo`                                                      |
| `bot_force_rebuild_id`                            | `app_force_rebuild_id`                                          |
| `okta_config.key_id`                              | `okta_config.private_key_id`; the old one never reached the app |
| `okta_config.github_user_field` (default `login`) | default `githubUsername`, as in the app                         |
| `okta_config.sync_rules` (`list(any)`)            | typed rules; unknown fields are an error                        |
| `api_gateway_config.cors_allow_origins`           | removed; webhooks don't need CORS                               |
| `lambda_config.runtime`                           | removed; always `provided.al2023`                               |

Other changes:

- **The function is built with the buildkit provider** instead of the
  docker-based artifact packager, and redeploys when its code changes. The
  packager's resources are forgotten from the state, not destroyed.
- **Secrets move to SSM** SecureString parameters. Set
  `ssm_config.store_secrets = false` to keep plain environment variables.
- **The function runs on `arm64`** by default, built for the architecture you
  choose; v0 always built an amd64 binary. Set
  `lambda_config.architecture = "x86_64"` to keep the v0 architecture.
- **The timeout is 600 seconds** by default, so a full Okta sync can finish.
- `github_app_config.installation_id` is optional; the app looks it up.
- `github_app_config.base_url` supports GitHub Enterprise Server.
- `create_team_if_missing` defaults to `false` in the app; set it on rules that
  should create teams.
- With `stage_name = "$default"`, routes have no base path; v0 set a base path
  of `/$default`, which broke every route.
- The PR bypass footer note is sent without a PR bypass channel.
- A schedule without its feature enabled is an error.
- API Gateway routes are throttled (burst 100, 50 requests per second).
- The module is checked with `terraform test` and tflint in CI.

## License

MIT Licensed. See [LICENSE](LICENSE) for full details.
