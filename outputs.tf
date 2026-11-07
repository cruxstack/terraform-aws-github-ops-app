# ================================================================== lambda ===

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = try(aws_lambda_function.this[0].arn, null)
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = try(aws_lambda_function.this[0].function_name, null)
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function"
  value       = try(aws_lambda_function.this[0].qualified_arn, null)
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = try(aws_lambda_function.this[0].invoke_arn, null)
}

# --------------------------------------------------------------------- iam ---

output "lambda_role_arn" {
  description = "ARN of the Lambda function's IAM role"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "lambda_role_name" {
  description = "Name of the Lambda function's IAM role"
  value       = try(aws_iam_role.this[0].name, null)
}

# -------------------------------------------------------------- cloudwatch ---

output "cloudwatch_log_group_name" {
  description = "Name of the Lambda function's log group"
  value       = try(aws_cloudwatch_log_group.lambda[0].name, null)
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the Lambda function's log group"
  value       = try(aws_cloudwatch_log_group.lambda[0].arn, null)
}

# ------------------------------------------------------------- api gateway ---

output "api_gateway_id" {
  description = "ID of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].id, null)
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].arn, null)
}

output "api_gateway_endpoint" {
  description = "Base URL of the API Gateway, without the stage"
  value       = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].execution_arn, null)
}

output "public_url" {
  description = "Base URL of the app's routes, including the stage"
  value       = local.public_url != "" ? local.public_url : null
}

output "webhook_url" {
  description = "Webhook URL to set in the GitHub App's settings"
  value       = local.public_url != "" ? "${local.public_url}/webhooks" : null
}

output "setup_url" {
  description = "URL of the GitHub App installer, when it is enabled"
  value       = local.public_url != "" && local.installer_enabled ? "${local.public_url}/setup" : null
}

output "webhook_secret" {
  description = "Webhook secret to set in the GitHub App's settings (generated if not provided); null when the installer creates the app"
  value       = local.enabled && !local.installer_enabled ? local.github_webhook_secret : null
  sensitive   = true
}

output "admin_token" {
  description = "Admin token for the /server/* and /scheduled/* endpoints (generated if not provided)"
  value       = local.enabled && local.admin_enabled ? local.admin_token : null
  sensitive   = true
}

# --------------------------------------------------------------------- ssm ---

output "ssm_parameter_prefix" {
  description = "SSM path under which secrets and the installer's credentials are kept"
  value       = local.enabled ? local.ssm_parameter_prefix : null
}

output "ssm_parameter_arns" {
  description = "ARNs of the secret parameters the module manages, by variable name"
  value       = { for name, param in aws_ssm_parameter.secret : name => param.arn }
}

# ============================================================= eventbridge ===

output "eventbridge_rule_arn" {
  description = "ARN of the Okta sync schedule rule, if enabled"
  value       = try(aws_cloudwatch_event_rule.okta_sync[0].arn, null)
}

output "eventbridge_rule_name" {
  description = "Name of the Okta sync schedule rule, if enabled"
  value       = try(aws_cloudwatch_event_rule.okta_sync[0].name, null)
}

output "eventbridge_security_alerts_rule_arn" {
  description = "ARN of the security alerts schedule rule, if enabled"
  value       = try(aws_cloudwatch_event_rule.security_alerts[0].arn, null)
}

output "eventbridge_security_alerts_rule_name" {
  description = "Name of the security alerts schedule rule, if enabled"
  value       = try(aws_cloudwatch_event_rule.security_alerts[0].name, null)
}
