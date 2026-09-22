# IAM — EC2 역할 3개(web·WAS·베스천) + 인스턴스 프로파일 3개, RDS 모니터링 역할 1개.
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

# 베스천 전용 역할 (2026-09-22 콘솔 생성). 최소 권한 원칙으로 CloudWatch Agent 로그 전송만 — SSM 은 일부러 안 붙였다
# (mc-ec2-role 을 재사용하면 Session Manager 까지 딸려 와서 별도 역할로 분리). 베스천 접속은 SSH(22) 그대로.
resource "aws_iam_role" "bastion" {
  name                 = "bastion-role"
  path                 = "/"
  description          = "bastion: CloudWatch Agent log shipping only"
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

resource "aws_iam_role_policy_attachment" "bastion_cloudwatch" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "bastion-role"
  path = "/"
  role = aws_iam_role.bastion.name
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
