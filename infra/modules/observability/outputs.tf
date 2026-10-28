output "sns_topic_arn" {
  description = "Alerts topic. Alarms and the budget publish here."
  value       = aws_sns_topic.alerts.arn
}

output "sns_kms_key_arn" {
  description = "CMK encrypting the alerts topic."
  value       = aws_kms_key.sns.arn
}

output "alarm_names" {
  description = "CloudWatch alarm names, by purpose."
  value = {
    elb_5xx         = aws_cloudwatch_metric_alarm.elb_5xx.alarm_name
    target_5xx_rate = aws_cloudwatch_metric_alarm.target_5xx_rate.alarm_name
    unhealthy_hosts = aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name
    latency_p95     = aws_cloudwatch_metric_alarm.latency_p95.alarm_name
    cpu             = aws_cloudwatch_metric_alarm.cpu.alarm_name
    memory          = aws_cloudwatch_metric_alarm.memory.alarm_name
  }
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "Console URL of the dashboard."
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "budget_name" {
  description = "Monthly cost budget name, or null when this stack doesn't own the budget."
  value       = try(aws_budgets_budget.monthly[0].name, null)
}
