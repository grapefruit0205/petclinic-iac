# Slack 알림 추가분 — 2026-09-28 kdt5 요청: WAS CPU 가 오를 때 · 인스턴스가 늘어날 때 · DB CPU 80% 이상일 때 Slack 으로.
# 모두 SNS mc-alerts(monitoring.tf) → Slack #petclinic-alerts. 기존 알람(web 요청 수 · CloudFront 5xx · WAF 차단)은 monitoring.tf.
# ASG 는 이름 글자로만 가리킨다 — compute.tf 에 발표 뒤 적용할 web 초안(시작 템플릿 v15 · max 6 · web_threads)이 섞여 있어서,
# aws_autoscaling_group 을 참조하면 이 파일만 -target 으로 plan/apply 할 때 그 초안이 딸려 들어온다.

locals {
  alert_asgs = { web = "web-test", was = "was-asg" }
}

# WAS 평균 CPU 50% 이상 3분 → Slack. 50 = WAS 목표 추적(compute.tf was_cpu)이 늘리기 시작하는 값 — "WAS 가 늘어난다" 와 같은 때 울린다.
# 목표 추적 알람(TargetTracking-was-asg-*)은 정책이 소유해 알림을 붙이면 안 되므로 따로 만든다. 내려가면(OK) 한 번 더 온다.
resource "aws_cloudwatch_metric_alarm" "was_cpu_high" {
  alarm_name          = "alarm-was-cpu-50"
  alarm_description   = "[WAS] 평균 CPU 50% 이상이 3분 이어지면 울림 — WAS 자동 증설 기준과 같은 값. 내려가면 OK 알림."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 50
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = local.alert_asgs.was
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# DB CPU 80% 이상 3분 → Slack. 주 DB · 읽기 복제본 따로 — 9/27 한계 시험에서 먼저 찬 곳은 복제본(99%), 주 DB 는 43%.
# 설명은 한국어(2026-09-28 kdt5 요청) — Slack 카드의 틀(제목 줄 · 기준 넘음 문구 · 그래프)은 AWS 가 영어로 만들고, 이 설명만 우리 글. ALARM · OK 둘 다에 붙는다.
resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  for_each = {
    main    = { id = aws_db_instance.main.identifier, desc = "[DB 주] database CPU 80% 이상이 3분 이어지면 울림 — 쓰기(예약 · 등록)가 몰릴 때. 내려가면 OK 알림." }
    replica = { id = aws_db_instance.replica.identifier, desc = "[DB 읽기 복제본] db-readonly CPU 80% 이상이 3분 이어지면 울림 — 조회가 몰릴 때(9/27 한계 시험의 병목). 내려가면 OK 알림." }
  }

  alarm_name          = "alarm-${each.value.id}-cpu-80"
  alarm_description   = each.value.desc
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ASG 에 새 인스턴스가 뜨면 → Slack. Auto Scaling 이 EventBridge 로 보내는 "EC2 Instance Launch Successful" 을
# 입력 변환기로 Q Developer 사용자 지정 알림 형식(version 1.0 · source custom)으로 바꿔 mc-alerts 에 보낸다.
# 늘어날 때뿐 아니라 교체(비정상 인스턴스 · 인스턴스 리프레시) 때도 온다.
# 넣는 값은 인스턴스 ID 하나 — EventBridge 는 입력 경로 값을 JSON 이스케이프하지 않아, 따옴표가 섞일 수 있는 Cause 는 안 넣는다.
# input_template 은 jsonencode 를 쓰지 않는다 — jsonencode 가 < > 를 유니코드 이스케이프(u003c · u003e)로 바꿔 <instance> 자리표시자가 안 먹는다.
resource "aws_cloudwatch_event_rule" "asg_launch" {
  for_each = local.alert_asgs

  name        = "${each.value}-instance-launch-slack"
  description = "${each.value} EC2 instance launch -> SNS mc-alerts -> Slack #petclinic-alerts"
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance Launch Successful"]
    detail = {
      AutoScalingGroupName = [each.value]
    }
  })
}

resource "aws_cloudwatch_event_target" "asg_launch" {
  for_each = local.alert_asgs

  rule      = aws_cloudwatch_event_rule.asg_launch[each.key].name
  target_id = "slack-mc-alerts"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      instance = "$.detail.EC2InstanceId"
    }
    input_template = <<-EOT
      {"version":"1.0","source":"custom","content":{"textType":"client-markdown","title":":arrow_up: ${upper(each.key)} 인스턴스 추가","description":"`${each.value}` 에 새 인스턴스 `<instance>` 가 떴습니다 (늘리기 또는 교체)."}}
    EOT
  }
}

# mc-alerts 토픽 정책 — 콘솔 기본 문장(같은 계정 주체만) 그대로 + 위 EventBridge 규칙 2개의 게시 허용.
# 기본 문장은 계정 안 주체만 허용해 서비스 주체(events.amazonaws.com)는 따로 열어야 한다. CloudWatch 알람 · Slack 구독은 기본 문장으로 된다.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "__default_policy_ID"
    Statement = [
      {
        Sid       = "__default_statement_ID"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
        ]
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "AWS:SourceOwner" = "723165663216" } }
      },
      {
        Sid       = "AllowEventBridgeAsgLaunch"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { ArnEquals = { "aws:SourceArn" = [for r in aws_cloudwatch_event_rule.asg_launch : r.arn] } }
      },
    ]
  })
}
