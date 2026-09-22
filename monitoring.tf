# 모니터링 · 알림 — 2026-09-21 콘솔 생성. ASG 목표 추적이 소유한 알람(TargetTracking-*)은 정책 리소스가 관리하므로 여기 없다.

# 알림 토픽. 정책은 콘솔 기본값(같은 계정만 게시·구독) 그대로라 생략.
resource "aws_sns_topic" "alerts" {
  name = "mc-alerts"
}

# 이메일 구독 1건 (확인 완료). confirmation_timeout_in_minutes · endpoint_auto_confirms 는 Terraform 전용 인자라 무시.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "dldnswosns@gmail.com"

  lifecycle {
    ignore_changes = [confirmation_timeout_in_minutes, endpoint_auto_confirms]
  }
}

# Public ALB → Targetgroup-web 의 타깃당 요청수(RequestCountPerTarget) 5분 합계가 20000 을 넘으면
# web 단계 정책(compute.tf web_reqcount) 실행 + 이메일 알림.
# ⚠️ statistic 이 Average 다 — RequestCountPerTarget 은 합계(Sum) 지표라 Average 는 1분 샘플 평균이 돼 임계치 의미가 달라진다. 콘솔에서 Sum 으로 바꾸는 게 맞다(WEB 담당 확인 필요).
resource "aws_cloudwatch_metric_alarm" "web_reqcount_high" {
  alarm_name          = "alarm-web-reqcount-high-20000"
  alarm_description   = "WEB ALB RequestCountPerTarget exceeds 20000 for 5 minutes.\nScale out WEB ASG when traffic increases."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCountPerTarget"
  statistic           = "Average"
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
