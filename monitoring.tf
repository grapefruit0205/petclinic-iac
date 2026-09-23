# 모니터링 · 알림 — 2026-09-21 콘솔 생성. ASG 목표 추적이 소유한 알람(TargetTracking-*)은 정책 리소스가 관리하므로 여기 없다.

# 알림 토픽. 정책은 콘솔 기본값(같은 계정만 게시·구독) 그대로라 생략.
# 구독자 = Slack #petclinic-alerts 하나 — Amazon Q Developer in chat applications(옛 AWS Chatbot), 2026-09-22 연결.
#   그 https 구독(global.sns-api.chatbot.amazonaws.com)은 Chatbot 서비스가 만들고 관리하므로 코드에 두지 않는다.
#   이메일 구독(jaewoon, 9/21)은 2026-09-23 해제 — 알림은 Slack 으로만.
resource "aws_sns_topic" "alerts" {
  name = "mc-alerts"
}

# Slack #petclinic-alerts ← mc-alerts (2026-09-22 18:15 콘솔 생성, 18:?? SNS 주제 연결). Slack 워크스페이스 승인(OAuth)은 콘솔에서만.
resource "aws_chatbot_slack_channel_configuration" "alerts" {
  provider = aws.us_east_2

  configuration_name          = "petclinic-alerts"
  iam_role_arn                = aws_iam_role.chatbot.arn
  slack_team_id               = "T8RKS1QE9"
  slack_channel_id            = "C0C3D4FF1EF"
  sns_topic_arns              = [aws_sns_topic.alerts.arn]
  guardrail_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  logging_level               = "NONE"
  user_authorization_required = false
}

# Public ALB → Targetgroup-web 의 타깃당 요청수(RequestCountPerTarget) 5분 합계가 20000 을 넘으면
# web 단계 정책(compute.tf web_reqcount) 실행 + Slack 알림(SNS mc-alerts).
# 통계 Sum (2026-09-23 15:0x kdt5, Average → Sum) — RequestCountPerTarget 은 합계 지표라 Average 면 1분 샘플 평균이 돼 web 2대 기준 667 RPS 가
# 5분 가야 울렸다. Sum 이면 "타깃당 5분 합계 > 20,000" = 2대 기준 총 134 RPS (부하 테스트에서 web 확장을 검증하려면 필요).
resource "aws_cloudwatch_metric_alarm" "web_reqcount_high" {
  alarm_name          = "alarm-web-reqcount-high-20000"
  alarm_description   = "WEB ALB RequestCountPerTarget exceeds 20000 for 5 minutes.\nScale out WEB ASG when traffic increases."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCountPerTarget"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 20000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    LoadBalancer = aws_lb.public.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.web_reqcount.arn, aws_sns_topic.alerts.arn]
}
