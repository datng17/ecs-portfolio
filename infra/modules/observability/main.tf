data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  topic_name  = "${var.name_prefix}-alerts"
  topic_arn   = "arn:${local.partition}:sns:${local.region}:${local.account_id}:${local.topic_name}"
  budget_name = coalesce(var.budget_name, "${var.name_prefix}-monthly-cost")

  alb_dimensions = { LoadBalancer = var.alb_arn_suffix }
  tg_dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  ecs_dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# KMS CMK for the alerts topic. The AWS-managed alias/aws/sns key can't be used:
# its policy can't be edited, so CloudWatch and Budgets can't publish to the topic.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "sns_kms" {
  # checkov:skip=CKV_AWS_109:Key policies must use Resource "*" (it means this key). Root statement is the AWS default.
  # checkov:skip=CKV_AWS_111:Key policies must use Resource "*" (it means this key). Root statement is the AWS default.
  # checkov:skip=CKV_AWS_356:Key policies must use Resource "*" (it means this key).
  statement {
    sid       = "EnableRootAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # The services that publish alerts need to create and read the message data key. This is the
  # statement form the SNS docs give for AWS event sources; which topic they may publish to is
  # restricted by the topic policy (aws:SourceAccount + aws:SourceArn).
  statement {
    sid       = "AllowAlertPublishersToUseKey"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "budgets.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "sns" {
  description             = "${var.name_prefix} alerts SNS topic"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.sns_kms.json
  tags                    = { Name = "${var.name_prefix}-alerts-kms" }
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${var.name_prefix}-alerts"
  target_key_id = aws_kms_key.sns.key_id
}

# ---------------------------------------------------------------------------
# Alerts topic + email subscription
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  kms_master_key_id = aws_kms_key.sns.arn
  tags              = { Name = local.topic_name }
}

data "aws_iam_policy_document" "sns_topic" {
  # Replaces the default topic policy, so the account-owner statement is restated.
  statement {
    sid    = "AllowAccountOwner"
    effect = "Allow"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]
    resources = [local.topic_arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarmsInThisAccount"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [local.topic_arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]
    }
  }

  statement {
    sid       = "AllowBudgetsInThisAccount"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [local.topic_arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:budgets::${local.account_id}:*"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["SNS:Publish"]
    resources = [local.topic_arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_topic.json
}

# Stays "PendingConfirmation" until the recipient clicks the link in the AWS email.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# Alarms. All notify on ALARM and on OK. Missing data is notBreaching: no traffic is not an
# error, and an outage still shows up as ELB 5xx and unhealthy hosts.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name        = "${var.name_prefix}-alb-elb-5xx"
  alarm_description = "ALB returned >= ${var.elb_5xx_threshold} 5xx itself (502/503/504) per ${var.alarm_period_seconds}s in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods. Usually no healthy targets or target timeouts."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  dimensions  = local.alb_dimensions
  statistic   = "Sum"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.elb_5xx_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx_rate" {
  alarm_name        = "${var.name_prefix}-alb-target-5xx-rate"
  alarm_description = "Target (nginx) 5xx > ${var.target_5xx_rate_threshold_percent}% of requests in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods (periods with < ${var.target_5xx_min_requests} requests count as 0). SLO error rate: 0.1%."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.target_5xx_rate_threshold_percent
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "rate"
    label       = "Target 5xx rate (%)"
    expression  = "IF(requests >= ${var.target_5xx_min_requests}, 100 * FILL(errors, 0) / requests, 0)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.tg_dimensions
      stat        = "Sum"
      period      = var.alarm_period_seconds
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.tg_dimensions
      stat        = "Sum"
      period      = var.alarm_period_seconds
    }
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name        = "${var.name_prefix}-tg-unhealthy-hosts"
  alarm_description = "At least ${var.unhealthy_host_threshold} target failing /healthz in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  dimensions  = local.tg_dimensions
  statistic   = "Maximum"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.unhealthy_host_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name        = "${var.name_prefix}-alb-latency-p95"
  alarm_description = "p95 TargetResponseTime > ${var.latency_p95_threshold_seconds * 1000} ms in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods (SLO: p95 < 300 ms)."

  namespace          = "AWS/ApplicationELB"
  metric_name        = "TargetResponseTime"
  dimensions         = local.tg_dimensions
  extended_statistic = "p95"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p95_threshold_seconds
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name        = "${var.name_prefix}-ecs-cpu-high"
  alarm_description = "Service average CPU > ${var.cpu_threshold_percent}% in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods. Autoscaling targets 60%, so this means scaling isn't keeping up or max capacity is reached."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions  = local.ecs_dimensions
  statistic   = "Average"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_threshold_percent
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  alarm_name        = "${var.name_prefix}-ecs-memory-high"
  alarm_description = "Service average memory > ${var.memory_threshold_percent}% in ${var.alarm_datapoints_to_alarm} of ${var.alarm_evaluation_periods} periods. Memory doesn't drive scaling; check for leaks or undersized tasks."

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  dimensions  = local.ecs_dimensions
  statistic   = "Average"

  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_threshold_percent
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
locals {
  alarm_arns = [
    aws_cloudwatch_metric_alarm.elb_5xx.arn,
    aws_cloudwatch_metric_alarm.target_5xx_rate.arn,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
    aws_cloudwatch_metric_alarm.latency_p95.arn,
    aws_cloudwatch_metric_alarm.cpu.arn,
    aws_cloudwatch_metric_alarm.memory.arn,
  ]

  alb  = ["LoadBalancer", var.alb_arn_suffix]
  tg   = ["LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix]
  ecsd = ["ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]

  dashboard_body = {
    widgets = [
      {
        type   = "alarm"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          title  = "Alarms"
          alarms = local.alarm_arns
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 8
        height = 6
        properties = {
          title   = "Requests (per minute)"
          region  = local.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            concat(["AWS/ApplicationELB", "RequestCount"], local.alb, [{ label = "Requests" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 3
        width  = 8
        height = 6
        properties = {
          title   = "HTTP errors (per minute)"
          region  = local.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb, [{ label = "ELB 5xx", color = "#d62728" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.tg, [{ label = "Target 5xx", color = "#ff7f0e" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count"], local.alb, [{ label = "ELB 4xx (incl. 403 without origin header)", color = "#9467bd" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 3
        width  = 8
        height = 6
        properties = {
          title  = "Target 5xx rate (%)"
          region = local.region
          view   = "timeSeries"
          period = 60
          metrics = [
            [{ expression = "100 * FILL(e5, 0) / req", label = "5xx rate %", id = "rate" }],
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.tg, [{ id = "e5", stat = "Sum", visible = false }]),
            concat(["AWS/ApplicationELB", "RequestCount"], local.tg, [{ id = "req", stat = "Sum", visible = false }]),
          ]
          annotations = {
            horizontal = [
              { label = "SLO 0.1%", value = 0.1 },
              { label = "Alarm", value = var.target_5xx_rate_threshold_percent, color = "#d62728" },
            ]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Target response time (seconds)"
          region = local.region
          view   = "timeSeries"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.tg, [{ stat = "p50", label = "p50" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.tg, [{ stat = "p95", label = "p95" }]),
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.tg, [{ stat = "p99", label = "p99" }]),
          ]
          annotations = {
            horizontal = [{ label = "SLO p95 300 ms", value = var.latency_p95_threshold_seconds, color = "#d62728" }]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Target health"
          region = local.region
          view   = "timeSeries"
          period = 60
          stat   = "Maximum"
          metrics = [
            concat(["AWS/ApplicationELB", "HealthyHostCount"], local.tg, [{ label = "Healthy", color = "#2ca02c" }]),
            concat(["AWS/ApplicationELB", "UnHealthyHostCount"], local.tg, [{ label = "Unhealthy", color = "#d62728" }]),
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 12
        height = 6
        properties = {
          title  = "Service CPU / memory (%)"
          region = local.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecsd, [{ label = "CPU" }]),
            concat(["AWS/ECS", "MemoryUtilization"], local.ecsd, [{ label = "Memory" }]),
          ]
          annotations = {
            horizontal = [
              { label = "Scaling target (CPU)", value = 60 },
              { label = "Alarm", value = var.cpu_threshold_percent, color = "#d62728" },
            ]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 15
        width  = 12
        height = 6
        properties = {
          title  = "Running tasks (Container Insights)"
          region = local.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            concat(["ECS/ContainerInsights", "RunningTaskCount"], local.ecsd, [{ label = "Running" }]),
            concat(["ECS/ContainerInsights", "DesiredTaskCount"], local.ecsd, [{ label = "Desired" }]),
          ]
          annotations = {
            horizontal = [
              { label = "Min", value = var.ecs_min_capacity },
              { label = "Max", value = var.ecs_max_capacity },
            ]
          }
          yAxis = { left = { min = 0 } }
        }
      },
    ]
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name_prefix
  dashboard_body = jsonencode(local.dashboard_body)
}

# ---------------------------------------------------------------------------
# Monthly cost budget (account-wide; tag filters need the payer account, see B-3)
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count = var.create_budget ? 1 : 0

  name         = local.budget_name
  budget_type  = "COST"
  limit_amount = format("%.2f", var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset(var.budget_actual_thresholds_percent)
    content {
      notification_type          = "ACTUAL"
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
      subscriber_email_addresses = [var.alert_email] # Direct email works even before the SNS subscription is confirmed.
    }
  }

  dynamic "notification" {
    for_each = toset(var.budget_forecast_thresholds_percent)
    content {
      notification_type          = "FORECASTED"
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
      subscriber_email_addresses = [var.alert_email]
    }
  }

  tags = { Name = local.budget_name }

  # Budgets checks the topic policy when the notification is saved.
  depends_on = [aws_sns_topic_policy.alerts]
}
