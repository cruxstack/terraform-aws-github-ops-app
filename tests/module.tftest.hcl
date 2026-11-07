# Runs the module with mocked providers, so these tests need no AWS account
# and build nothing. Run with: terraform test

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/test"
    }
  }
  mock_resource "aws_ssm_parameter" {
    defaults = {
      arn = "arn:aws:ssm:us-east-1:111122223333:parameter/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:111122223333:log-group:mock"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      api_endpoint  = "https://abc123.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:111122223333:abc123"
    }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:111122223333:rule/mock"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:111122223333:function:test"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/functions/test/invocations"
    }
  }
}

mock_provider "buildkit" {}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "generated-secret-0123456789abcdef"
    }
  }
}

variables {
  name = "test"
  github_app_config = {
    org         = "acme"
    app_id      = "123456"
    private_key = "-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----"
  }
}

run "defaults" {
  assert {
    condition = alltrue([
      aws_lambda_function.this[0].runtime == "provided.al2023",
      aws_lambda_function.this[0].handler == "bootstrap",
      aws_lambda_function.this[0].architectures[0] == "arm64",
      aws_lambda_function.this[0].timeout == 600,
      aws_lambda_function.this[0].source_code_hash == buildkit_artifact.app[0].artifact_sha256,
    ])
    error_message = "the function should run the arm64 go binary with a long timeout and redeploy when the artifact changes"
  }

  assert {
    condition = alltrue([
      buildkit_artifact.app[0].build_args.APP_VERSION == "v1.0.0",
      buildkit_artifact.app[0].build_args.GOARCH == "arm64",
      buildkit_artifact.app[0].artifact_dst_path == "./dist/test/package.zip",
    ])
    error_message = "the artifact should be built at the pinned version for arm64, at a path unique to the instance"
  }

  assert {
    condition = nonsensitive(alltrue([
      aws_lambda_function.this[0].environment[0].variables.APP_LOG_LEVEL == "info",
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_ORG == "acme",
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_APP_ID == "123456",
      aws_lambda_function.this[0].environment[0].variables.APP_BASE_PATH == "/v1",
      aws_lambda_function.this[0].environment[0].variables.APP_PUBLIC_URL == "https://abc123.execute-api.us-east-1.amazonaws.com/v1",
      !contains(keys(aws_lambda_function.this[0].environment[0].variables), "APP_GITHUB_INSTALLATION_ID"),
      !contains(keys(aws_lambda_function.this[0].environment[0].variables), "APP_OKTA_DOMAIN"),
    ]))
    error_message = "the function should get the github settings and the stage's base path"
  }

  assert {
    condition = alltrue([
      toset(keys(aws_ssm_parameter.secret)) == toset(["APP_ADMIN_TOKEN", "APP_GITHUB_APP_PRIVATE_KEY", "APP_GITHUB_WEBHOOK_SECRET"]),
      aws_ssm_parameter.secret["APP_GITHUB_WEBHOOK_SECRET"].name == "/test/APP_GITHUB_WEBHOOK_SECRET",
      aws_ssm_parameter.secret["APP_GITHUB_WEBHOOK_SECRET"].type == "SecureString",
      nonsensitive(aws_ssm_parameter.secret["APP_GITHUB_WEBHOOK_SECRET"].value) == "generated-secret-0123456789abcdef",
    ])
    error_message = "the private key, a generated webhook secret, and a generated admin token should be stored in ssm"
  }

  assert {
    condition = nonsensitive(alltrue([
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_APP_PRIVATE_KEY == "arn:aws:ssm:us-east-1:111122223333:parameter/mock",
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_WEBHOOK_SECRET == "arn:aws:ssm:us-east-1:111122223333:parameter/mock",
      aws_lambda_function.this[0].environment[0].variables.APP_ADMIN_TOKEN == "arn:aws:ssm:us-east-1:111122223333:parameter/mock",
    ]))
    error_message = "the function should get secrets as ssm parameter arns, not their values"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.this[0].statement :
      s.sid == "ReadSecrets" && toset(s.actions) == toset(["ssm:GetParameter"]) && toset(s.resources) == toset([for p in aws_ssm_parameter.secret : p.arn])
    ])
    error_message = "the function should be allowed to read exactly the secret parameters"
  }

  assert {
    condition = alltrue([
      output.webhook_url == "https://abc123.execute-api.us-east-1.amazonaws.com/v1/webhooks",
      output.setup_url == null,
      length(aws_cloudwatch_event_rule.okta_sync) == 0,
      length(aws_cloudwatch_event_rule.security_alerts) == 0,
      aws_apigatewayv2_stage.this[0].default_route_settings[0].throttling_rate_limit == 50,
    ])
    error_message = "the webhook url should include the stage, with no schedules and throttled routes"
  }
}

run "plain_secrets_and_x86" {
  variables {
    ssm_config         = { store_secrets = false }
    admin_token_config = { token = "an-admin-token-0123456789" }
    lambda_config      = { architecture = "x86_64" }
    log_level          = "debug"
  }

  assert {
    condition = alltrue([
      length(aws_ssm_parameter.secret) == 0,
      nonsensitive(aws_lambda_function.this[0].environment[0].variables.APP_ADMIN_TOKEN) == "an-admin-token-0123456789",
      nonsensitive(aws_lambda_function.this[0].environment[0].variables.APP_LOG_LEVEL) == "debug",
      length(random_password.admin_token) == 0,
      buildkit_artifact.app[0].build_args.GOARCH == "amd64",
    ])
    error_message = "without ssm, secrets should be plain variables, and x86_64 should build an amd64 binary"
  }
}

run "installer" {
  variables {
    github_app_config = { org = "acme" }
    installer_config  = { enabled = true }
    ssm_config        = { parameter_prefix = "/ops/github/" }
  }

  assert {
    condition = nonsensitive(alltrue([
      aws_lambda_function.this[0].environment[0].variables.GITHUB_APP_INSTALLER_ENABLED == "true",
      aws_lambda_function.this[0].environment[0].variables.STORAGE_MODE == "aws-ssm",
      aws_lambda_function.this[0].environment[0].variables.AWS_SSM_PARAMETER_PREFIX == "/ops/github/",
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_APP_ID == "arn:aws:ssm:us-east-1:111122223333:parameter/ops/github/APP_GITHUB_APP_ID",
      aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_WEBHOOK_SECRET == "arn:aws:ssm:us-east-1:111122223333:parameter/ops/github/APP_GITHUB_WEBHOOK_SECRET",
    ]))
    error_message = "the function should read the github app credentials the installer saves under the prefix"
  }

  assert {
    condition = alltrue([
      toset(keys(aws_ssm_parameter.secret)) == toset(["APP_ADMIN_TOKEN"]),
      length(random_password.webhook_secret) == 0,
      output.setup_url == "https://abc123.execute-api.us-east-1.amazonaws.com/v1/setup",
      output.webhook_secret == null,
    ])
    error_message = "the module should not create the github app's credentials in installer mode"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.this[0].statement :
      s.sid == "InstallerCredentials" && contains(s.actions, "ssm:PutParameter") && toset(s.resources) == toset(["arn:aws:ssm:us-east-1:111122223333:parameter/ops/github/*"])
    ])
    error_message = "the installer should be allowed to save parameters under the prefix only"
  }
}

run "okta_slack_and_schedules" {
  variables {
    okta_config = {
      enabled        = true
      domain         = "acme.okta.com"
      client_id      = "client"
      private_key    = "okta-key"
      private_key_id = "kid-1"
      sync_rules = [
        { okta_group_name = "Engineering", github_team_name = "eng", create_team_if_missing = true },
        { okta_group_pattern = "^gh-", strip_prefix = "gh-" },
      ]
    }
    okta_sync_schedule     = { enabled = true }
    security_alerts_config = { enabled = true, min_age_days = 0 }
    security_alerts_schedule = {
      enabled = true
    }
    pr_compliance_config = {
      enabled            = true
      monitored_branches = ["main", "release/*"]
      slack_footer_note  = "_see the policy_"
    }
    slack_config = {
      enabled = true
      token   = "xoxb-1"
      channel = "C1"
    }
  }

  assert {
    condition = nonsensitive(alltrue([
      aws_lambda_function.this[0].environment[0].variables.APP_OKTA_PRIVATE_KEY_ID == "kid-1",
      aws_lambda_function.this[0].environment[0].variables.APP_OKTA_GITHUB_USER_FIELD == "githubUsername",
      aws_lambda_function.this[0].environment[0].variables.APP_OKTA_SYNC_RULES == jsonencode([
        { create_team_if_missing = true, github_team_name = "eng", okta_group_name = "Engineering" },
        { okta_group_pattern = "^gh-", strip_prefix = "gh-" },
      ]),
      !contains(keys(aws_lambda_function.this[0].environment[0].variables), "APP_OKTA_KEY_ID"),
      !contains(keys(aws_lambda_function.this[0].environment[0].variables), "APP_OKTA_SCOPES"),
    ]))
    error_message = "okta settings should use the app's variable names, and rules should leave out unset fields"
  }

  assert {
    condition = nonsensitive(alltrue([
      aws_lambda_function.this[0].environment[0].variables.APP_SLACK_FOOTER_NOTE_PR_BYPASS == "_see the policy_",
      aws_lambda_function.this[0].environment[0].variables.APP_PR_MONITORED_BRANCHES == "main,release/*",
      aws_lambda_function.this[0].environment[0].variables.APP_SECURITY_ALERTS_MIN_AGE_DAYS == "0",
      contains(keys(aws_ssm_parameter.secret), "APP_OKTA_PRIVATE_KEY"),
      contains(keys(aws_ssm_parameter.secret), "APP_SLACK_TOKEN"),
    ]))
    error_message = "the footer note should not depend on a pr bypass channel, and the okta key and slack token should be in ssm"
  }

  assert {
    condition = alltrue([
      length(aws_cloudwatch_event_rule.okta_sync) == 1,
      length(aws_cloudwatch_event_rule.security_alerts) == 1,
      strcontains(aws_cloudwatch_event_target.okta_sync[0].input_transformer[0].input_template, "\"detail\": {\"action\": \"okta-sync\"}"),
      strcontains(aws_cloudwatch_event_target.security_alerts[0].input_transformer[0].input_template, "\"detail\": {\"action\": \"security-alerts\"}"),
    ])
    error_message = "each schedule should send its action"
  }
}

run "default_stage" {
  variables {
    api_gateway_config = { stage_name = "$default" }
  }

  assert {
    condition = alltrue([
      !nonsensitive(contains(keys(aws_lambda_function.this[0].environment[0].variables), "APP_BASE_PATH")),
      output.webhook_url == "https://abc123.execute-api.us-east-1.amazonaws.com/webhooks",
    ])
    error_message = "the $default stage has no base path"
  }
}

run "github_enterprise_and_installation" {
  variables {
    github_app_config = {
      org             = "acme"
      app_id          = "1"
      private_key     = "key"
      installation_id = "42"
      base_url        = "https://github.example.com/api/v3"
      webhook_secret  = "a-webhook-secret-0123456789"
    }
  }

  assert {
    condition = alltrue([
      nonsensitive(aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_INSTALLATION_ID) == "42",
      nonsensitive(aws_lambda_function.this[0].environment[0].variables.APP_GITHUB_BASE_URL) == "https://github.example.com/api/v3",
      nonsensitive(aws_ssm_parameter.secret["APP_GITHUB_WEBHOOK_SECRET"].value) == "a-webhook-secret-0123456789",
      length(random_password.webhook_secret) == 0,
    ])
    error_message = "given settings should be passed through, and a given webhook secret used"
  }
}

run "secret_given_as_parameter_arn" {
  variables {
    slack_config = {
      enabled = true
      token   = "arn:aws:ssm:us-east-1:111122223333:parameter/slack/token"
      channel = "C1"
    }
  }

  assert {
    condition = alltrue([
      !contains(keys(aws_ssm_parameter.secret), "APP_SLACK_TOKEN"),
      nonsensitive(aws_lambda_function.this[0].environment[0].variables.APP_SLACK_TOKEN) == "arn:aws:ssm:us-east-1:111122223333:parameter/slack/token",
      anytrue([
        for s in data.aws_iam_policy_document.this[0].statement :
        s.sid == "ReadParameters" && contains(s.resources, "arn:aws:ssm:us-east-1:111122223333:parameter/slack/token")
      ]),
    ])
    error_message = "a secret given as a parameter arn should be passed as is and made readable, not stored again"
  }
}

run "disabled" {
  variables {
    enabled = false
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.this) == 0,
      length(buildkit_artifact.app) == 0,
      length(aws_ssm_parameter.secret) == 0,
      length(aws_apigatewayv2_api.this) == 0,
    ])
    error_message = "a disabled module should create nothing"
  }
}

# ------------------------------------------------------------- validation ---

run "rejects_missing_credentials" {
  command = plan

  variables {
    github_app_config = { org = "acme" }
  }

  expect_failures = [aws_lambda_function.this]
}

run "rejects_rule_with_name_and_pattern" {
  command = plan

  variables {
    okta_config = {
      enabled     = true
      domain      = "acme.okta.com"
      client_id   = "client"
      private_key = "key"
      sync_rules  = [{ okta_group_name = "eng", okta_group_pattern = "^eng" }]
    }
  }

  expect_failures = [var.okta_config]
}

run "rejects_pattern_with_team_name" {
  command = plan

  variables {
    okta_config = {
      enabled     = true
      domain      = "acme.okta.com"
      client_id   = "client"
      private_key = "key"
      sync_rules  = [{ okta_group_pattern = "^eng", github_team_name = "all" }]
    }
  }

  expect_failures = [var.okta_config]
}

run "rejects_okta_domain_with_scheme" {
  command = plan

  variables {
    okta_config = {
      enabled     = true
      domain      = "https://acme.okta.com"
      client_id   = "client"
      private_key = "key"
      sync_rules  = [{ okta_group_name = "eng" }]
    }
  }

  expect_failures = [var.okta_config]
}

run "rejects_short_admin_token" {
  command = plan

  variables {
    admin_token_config = { token = "short" }
  }

  expect_failures = [var.admin_token_config]
}

run "rejects_schedule_without_feature" {
  command = plan

  variables {
    okta_sync_schedule = { enabled = true }
  }

  expect_failures = [aws_cloudwatch_event_rule.okta_sync]
}

run "rejects_bad_stage_name" {
  command = plan

  variables {
    api_gateway_config = { stage_name = "v1/beta" }
  }

  expect_failures = [var.api_gateway_config]
}
