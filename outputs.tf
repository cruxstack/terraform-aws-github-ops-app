# ================================================================== lambda ===

output "lambda_function_arn" {
  description = "ARN of the GitHub Ops App Lambda function"
  value       = try(aws_lambda_function.this[0].arn, null)
}

output "lambda_function_name" {
  description = "Name of the GitHub Ops App Lambda function"
  value       = try(aws_lambda_function.this[0].function_name, null)
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the GitHub Ops App Lambda function"
  value       = try(aws_lambda_function.this[0].qualified_arn, null)
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the GitHub Ops App Lambda function"
  value       = try(aws_lambda_function.this[0].invoke_arn, null)
}

# --------------------------------------------------------------------- iam ---

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "lambda_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = try(aws_iam_role.this[0].name, null)
}

# --------------------------------------------------------------- cloudwatch ---

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function logs"
  value       = try(aws_cloudwatch_log_group.lambda[0].name, null)
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function logs"
  value       = try(aws_cloudwatch_log_group.lambda[0].arn, null)
}

# -------------------------------------------------------------- api gateway ---

output "api_gateway_id" {
  description = "ID of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].id, null)
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].arn, null)
}

output "api_gateway_endpoint" {
  description = "Base URL of the API Gateway (use this as the GitHub webhook URL base)"
  value       = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].execution_arn, null)
}

output "webhook_url" {
  description = "Full webhook URL to configure in GitHub App settings"
  value       = try("${aws_apigatewayv2_stage.this[0].invoke_url}/webhooks", null)
}

output "webhook_secret" {
  description = "Webhook secret to configure in GitHub App settings (generated if not provided)"
  value       = try(local.github_webhook_secret, null)
  sensitive   = true
}

output "admin_token" {
  description = "Admin token for accessing /server/* and /scheduled/* endpoints (generated if not provided)"
  value       = try(local.admin_token, null)
  sensitive   = true
}

# ============================================================== eventbridge ===

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled Okta sync (if enabled)"
  value       = try(aws_cloudwatch_event_rule.okta_sync[0].arn, null)
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled Okta sync (if enabled)"
  value       = try(aws_cloudwatch_event_rule.okta_sync[0].name, null)
}
