# IAM — EC2 역할 2개 + 인스턴스 프로파일 2개, RDS 관련 역할 2개.
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

# RDS Proxy 가 Secrets Manager 의 DB 자격증명을 읽는 역할 (콘솔 마법사가 생성).
resource "aws_iam_role" "rds_proxy" {
  name                 = "rds-proxy-role-1789628580044"
  path                 = "/service-role/"
  description          = "Allows RDS Proxy access to database connection credentials"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = "723165663216" }
      }
    }]
  })
}

resource "aws_iam_policy" "rds_proxy" {
  name = "rds-proxy-policy-1789628580044"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetSecretValue"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:ap-northeast-2:723165663216:secret:rds!db-0e2be729-c1ce-47c8-9f20-4c5c631e3533-ibt651"]
      },
      {
        Sid      = "DecryptSecretValue"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["arn:aws:kms:ap-northeast-2:723165663216:key/7858219a-eb53-4695-9f92-931ec6fa4432"]
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.ap-northeast-2.amazonaws.com" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["arn:aws:rds-db:ap-northeast-2:723165663216:dbuser:db-VPGRJE4O6M6WSIXGJDSIVPA3QY/admin"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy.arn
}
