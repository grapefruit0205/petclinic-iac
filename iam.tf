# IAM — EC2 역할 3개(web·WAS·CloudWatch 전용) + 인스턴스 프로파일 3개, Chatbot 역할 1개, RDS 모니터링 역할 1개.
# 관리형 정책 연결은 aws_iam_role_policy_attachment 로 분리 (역할 블록의 managed_policy_arns 는 쓰지 않는다).

# ASG 웹 · web-ami 가 쓰는 역할. SSM 관리 노드 + CloudWatch Agent 로그 전송.
resource "aws_iam_role" "ec2" {
  name                 = "mc-ec2-role"
  path                 = "/"
  description          = "Allows EC2 instances to call AWS services on your behalf."
  max_session_duration = 14400

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "mc-ec2-role"
  path = "/"
  role = aws_iam_role.ec2.name
}

# web(시작 템플릿 v8)·베스천 공용 — CloudWatch Agent 로그·지표 전송만, SSM 없음 (최소 권한). 2026-09-22 13:44 콘솔 생성.
# ⚠️ 역할 이름이 AWS 관리형 정책 이름과 같다(CloudWatchAgentServerPolicy) — 정책이 아니라 역할이다.
# 17:33 web LT v8, 17:36 베스천이 이 프로파일로 전환. 같은 권한이던 bastion-role 은 정리하기로 결정(2026-09-23) — 코드·state 에서 제거.
# 참고: 이 정책의 ssm:GetParameter 는 parameter/AmazonCloudWatch-* 만 허용 → /petclinic/cwagent/* 파라미터는 못 읽는다.
resource "aws_iam_role" "cw_agent" {
  name                 = "CloudWatchAgentServerPolicy"
  path                 = "/"
  description          = "Allows EC2 instances to call AWS services on your behalf."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.cw_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "cw_agent" {
  name = "CloudWatchAgentServerPolicy"
  path = "/"
  role = aws_iam_role.cw_agent.name
}

# Slack 알림(AWS Chatbot) 채널 역할 — 2026-09-22 18:15 콘솔 템플릿이 생성. 알림 카드에 CloudWatch 그래프를 붙이는 읽기 권한.
resource "aws_iam_role" "chatbot" {
  name                 = "chatbot-petclinic-alerts"
  path                 = "/service-role/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "chatbot_notifications" {
  name        = "AWS-Chatbot-NotificationsOnly-Policy-f4d7e8f8-6429-4ff2-8088-501c6ecac3f5"
  path        = "/service-role/"
  description = "NotificationsOnly policy for AWS-Chatbot"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "chatbot_notifications" {
  role       = aws_iam_role.chatbot.name
  policy_arn = aws_iam_policy.chatbot_notifications.arn
}

# 콘솔 템플릿 "Amazon Q Developer 액세스 권한" — 채널에서 Q 에게 질문하는 기능. 알림만 쓰면 불필요(떼도 됨).
resource "aws_iam_role_policy_attachment" "chatbot_q" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonQDeveloperAccess"
}


# WAS-test-a 역할. ⚠️ AmazonRDSFullAccess — 과잉 권한. SSM 정책은 없어 SSM 미관리.
resource "aws_iam_role" "was" {
  name                 = "was-test-iam"
  path                 = "/"
  description          = "test-was rds full acess"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "was_rds" {
  role       = aws_iam_role.was.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_instance_profile" "was" {
  name = "was-test-iam"
  path = "/"
  role = aws_iam_role.was.name
}

# 2026-09-21 15:02 KST semin: WAS 가 부팅 때 RDS 관리형 시크릿에서 DB 비밀번호를 읽도록 (부하 시나리오 v2 §7 의 user data 흐름).
# 여전히 SSM·CloudWatch 정책은 없다.
resource "aws_iam_role_policy" "was_read_rds_secret" {
  name = "PetclinicReadRdsSecret"
  role = aws_iam_role.was.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadPetclinicRdsSecret"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

# RDS 향상된 모니터링용 역할 — 만들어져 있지만 database-1 은 monitoring_interval = 0 이라 미사용.
resource "aws_iam_role" "rds_monitoring" {
  name                 = "rds-monitoring-role"
  path                 = "/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = ""
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# (RDS Proxy 용 역할 rds-proxy-role-1789628580044 · 정책 · 연결은 프록시와 함께 2026-09-22 09:00 KST 삭제 — 코드·state 에서 제거.)
