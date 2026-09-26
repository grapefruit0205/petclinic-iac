# 모니터링 · 알림 — 2026-09-21 콘솔 생성. ASG 목표 추적이 소유한 알람(TargetTracking-*)은 정책 리소스가 관리하므로 여기 없다.
# 알람 3개(web 요청 수 · CloudFront 5xx · WAF 차단) → SNS 3개 → Slack, 그리고 CloudTrail.

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
  sns_topic_arns              = [aws_sns_topic.alerts.arn, aws_sns_topic.cf_5xx.arn, aws_sns_topic.waf_block.arn] # 뒤 2개는 2026-09-24 yena 추가(us-east-1)
  guardrail_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  logging_level               = "NONE"
  user_authorization_required = false
}

# Public ALB → Targetgroup-web 의 타깃당 요청수(RequestCountPerTarget) 5분 합계가 20000 을 넘으면
# web 단계 정책(compute.tf web_reqcount) 실행 + Slack 알림(SNS mc-alerts).
# 통계 Sum (2026-09-23 15:0x kdt5, Average → Sum) — RequestCountPerTarget 은 합계 지표라 Average 면 1분 샘플 평균이 돼 web 2대 기준 667 RPS 가
# 5분 가야 울렸다. Sum 이면 "타깃당 5분 합계 > 20,000" = 2대 기준 총 134 RPS (부하 테스트에서 web 확장을 검증하려면 필요).
# 2026-09-24 01:23 kdt5 가 S5 준비 중 콘솔에서 삭제 → 9/24 이 코드 그대로 다시 만듦 (terraform apply -target).
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

# --- us-east-1 알람 2개 (2026-09-24 yena 콘솔 생성) — CloudFront·WAF 지표는 us-east-1 에만 있어 알람도 거기 ---
# 토픽마다 Slack #petclinic-alerts 로 가는 https 구독이 있다 — Chatbot 이 만들고 관리하므로 코드에 두지 않는다(mc-alerts 와 같음).
# (18:48 에 만든 cf-slack-alerts 토픽은 지금 없다 — 18:51 CF-5xxerror-alerts 로 다시 만든 것으로 보임.)
resource "aws_sns_topic" "cf_5xx" {
  provider     = aws.us_east_1
  name         = "CF-5xxerror-alerts"
  display_name = "CF-5xxerror-alerts"
}

resource "aws_sns_topic" "waf_block" {
  provider     = aws.us_east_1
  name         = "WAF-Block-Alert"
  display_name = "WAF-Block-Alert"
}

# CloudFront 5xx 비율 5분 평균 ≥ 5% 가 3번 연속(15분). 18:59 생성 · 19:03 수정.
resource "aws_cloudwatch_metric_alarm" "cf_5xx" {
  provider            = aws.us_east_1
  alarm_name          = "CF-Prod-5xxError-Spike"
  alarm_description   = "# CloudFront 5xx 에러율 급증 알람\n* **발생 원인**: CloudFront에서 오리진(ALB/백엔드)으로 요청을 넘기는 과정에서 5xx 서버 에러가 임계값(5%) 이상 발생했습니다.\n* **조치 가이드**: \n  1. EC2/ALB 타겟 그룹의 헬스체크 상태를 확인하세요.\n  2. WAS(애플리케이션) 서버의 부하 또는 에러 로그를 확인하세요."
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    Region         = "Global"
    DistributionId = aws_cloudfront_distribution.main.id
  }
  alarm_actions = [aws_sns_topic.cf_5xx.arn]
}

# WAF 가 차단한 요청(전체 규칙) 5분 합계 > 500. 16:35 생성. ⚠️ 지금 web ACL 의 룰이 전부 Count 라(edge.tf) 차단이 0 → 이 알람은 울릴 수 없다.
resource "aws_cloudwatch_metric_alarm" "waf_block" {
  provider            = aws.us_east_1
  alarm_name          = "WAF-Block-Alert"
  alarm_description   = "WAF에서 5분 내 500건 이상의 차단이 발생했습니다. 봇 트래픽 또는 공격을 확인하세요."
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    WebACL = aws_wafv2_web_acl.cloudfront.name
    Rule   = "ALL"
  }
  alarm_actions = [aws_sns_topic.waf_block.arn]

  tags = {
    service = "petclinic"
  }
}

# --- CloudTrail (2026-09-24 01:26 KST jaewoon 콘솔 생성) — 계정 전체 API 기록 ---
# 모든 리전 · 글로벌 서비스(IAM 등) 포함 · 관리 이벤트만(데이터 이벤트 없음) · 로그 파일 무결성 검증 켬.
# 로그는 KMS 고객 관리형 키로 암호화 — 키(별칭 alias/alias/cloudtrail-logs, 트레일과 함께 콘솔 생성)는 코드로 관리하지 않고 ARN 만 쓴다.
# CloudWatch Logs 전송은 없음.
resource "aws_cloudtrail" "main" {
  name                          = "cloud-logs-all"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = "arn:aws:kms:ap-northeast-2:723165663216:key/95c50b22-4e78-4c91-b5ea-5a4b4b1488fa"

  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }
}

# --- RDS 감사 로그 → S3 : Firehose RDS-Audit-PUT-S3 (2026-09-24 jaewoon 콘솔 작업 중) ---
# 18:40 첫 생성은 역할 오류로 실패 → 20:41 생성(목적지 mc-logs-petclinic) → 22:02 목적지를 전용 버킷 rds_audit(storage.tf)로 변경.
# 입력은 Direct PUT 인데 아직 넣는 쪽이 없다(감사 로그 그룹 구독 필터 0 · Lambda 0, 22:07 확인) → 들어온 레코드 0.
# 5분 또는 64 MB 마다 GZIP 으로 묶어 rds/audit/year=…/month=…/day=…/ (서울 시간 날짜) 에 쓴다. 실패분은 rds/audit/error/.
resource "aws_kinesis_firehose_delivery_stream" "rds_audit" {
  name        = "RDS-Audit-PUT-S3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_rds_audit.arn
    bucket_arn          = aws_s3_bucket.rds_audit.arn
    prefix              = "rds/audit/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "rds/audit/error/"
    buffering_size      = 64
    buffering_interval  = 300
    compression_format  = "GZIP"
    file_extension      = ".gz"
    custom_time_zone    = "Asia/Seoul"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_rds_audit.name
      log_stream_name = "DestinationDelivery"
    }
  }
}

# 대시보드 — 2026-09-24 18:38 KST 마지막 저장(콘솔, 만든 사람은 CloudTrail 조회로 안 나옴). CloudFront 지표 위젯 1개.
# 부하 테스트 화면 공유용 대시보드 11칸 — 2026-09-26 16:23~16:41 KST kdt5 가 CLI put-dashboard 로 생성
# (원본 loadtest/cloudwatch-dashboard.json 과 같음). 칸을 바꾸면 이 JSON 을 고치고 plan.
resource "aws_cloudwatch_dashboard" "loadtest" {
  dashboard_name = "petclinic-loadtest"
  dashboard_body = file("${path.module}/cloudwatch/dashboard-petclinic-loadtest.json")
}

resource "aws_cloudwatch_dashboard" "traffic" {
  dashboard_name = "PetClinic-Traffic-Dashboard"

  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      x      = 0
      y      = 0
      width  = 6
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = "us-east-1"
        metrics = [
          ["AWS/CloudFront", "5xxErrorRate", "Region", "Global", "DistributionId", "E1F6M0QDUUT8AG"],
          [".", "Requests", ".", ".", ".", "."],
          [".", "4xxErrorRate", ".", ".", ".", "."],
          [".", "BytesDownloaded", ".", ".", ".", "."],
        ]
      }
    }]
  })
}
