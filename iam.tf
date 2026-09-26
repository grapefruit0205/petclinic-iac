# IAM — EC2 역할 4개(mc-ec2-role · WAS · CloudWatch 전용 · web-iam) + 인스턴스 프로파일 4개, Chatbot 역할 1개, RDS 모니터링 역할 1개, Firehose 역할 1개.
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

# 2026-09-24 19:58 KST yena 콘솔 생성 — web 용으로 보이는 새 역할 (CloudWatch Agent 만). 아직 어떤 시작 템플릿·인스턴스도 안 쓴다
# (web LT v13 은 위 cw_agent 프로파일). 작업 중일 수 있어 권한이 더 붙으면 여기 연결 추가.
resource "aws_iam_role" "web" {
  name                 = "web-iam"
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

resource "aws_iam_role_policy_attachment" "web_cloudwatch" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "web" {
  name = "web-iam"
  path = "/"
  role = aws_iam_role.web.name
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


# WAS 역할 (ASG WAS · WAS-test-a · was-gg2). 설명의 "rds full acess" 는 옛 이름 그대로 — 그 정책은 2026-09-23 떼어냈다.
# 붙은 것: 시크릿 읽기(인라인) · SSM Core · CloudWatch Agent. 과잉 권한이던 AmazonRDSFullAccess 는 없음.
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

# (AmazonRDSFullAccess 는 2026-09-23 23:33 KST semin 이 콘솔에서 떼어냄 — WAS 는 DB 에 SQL 로만 붙고 RDS API 는 안 쓴다. 코드에서 제거.)

# 2026-09-22 17:14 KST yena: SSM 관리 노드 (Session Manager 접속 · Run Command).
resource "aws_iam_role_policy_attachment" "was_ssm" {
  role       = aws_iam_role.was.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 2026-09-23 23:30 KST semin: CloudWatch Agent 로그 전송 — 붙인 직후 23:31 WAS 로그 그룹 3개가 생겼다(storage.tf).
resource "aws_iam_role_policy_attachment" "was_cloudwatch" {
  role       = aws_iam_role.was.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "was" {
  name = "was-test-iam"
  path = "/"
  role = aws_iam_role.was.name
}

# 2026-09-21 15:02 KST semin: WAS 가 부팅 때 RDS 관리형 시크릿에서 DB 비밀번호를 읽도록 (부하 시나리오 v2 §7 의 user data 흐름).
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

# Firehose RDS-Audit-PUT-S3(monitoring.tf) 역할 — 2026-09-24 18:40 KST jaewoon 이 Firehose 콘솔에서 생성.
# 정책 2개 (2026-09-24 22:50 ~ 09-25 00:28 KST jaewoon 콘솔 정리 반영):
#   central_logs : 처음(20:40) 콘솔 기본 템플릿. 22:50 S3 문장만 전용 버킷으로 바꾼 새 버전 → 22:52 역할에서 뗌(연결 0, 정리 후보).
#   rds_audit    : "-alt". 00:28 필요한 두 문장(S3 전용 버킷 · Firehose 오류 로그)만 남긴 버전 — 역할에 붙은 건 이것 하나.
# 역할 신뢰 정책에 aws:SourceAccount 조건 추가 (2026-09-25 00:24 KST).
resource "aws_iam_role" "firehose_rds_audit" {
  name                 = "KinesisFirehoseServiceRole-RDS-Audi-ap-northeast-2-1790239262890"
  path                 = "/service-role/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = "723165663216" } }
    }]
  })
}

locals {
  firehose_placeholder = "%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
  firehose_rds_audit_policies = {
    central_logs = { name_suffix = "", policy = local.firehose_template_policy }
    rds_audit    = { name_suffix = "-alt", policy = local.firehose_rds_audit_policy }
  }

  # -alt (쓰는 쪽): 전용 버킷 쓰기 + Firehose 오류 로그
  firehose_rds_audit_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FirehoseToS3"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject",
          "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject",
        ]
        Resource = [aws_s3_bucket.rds_audit.arn, "${aws_s3_bucket.rds_audit.arn}/*"]
      },
      {
        Sid      = "FirehoseErrorLogging"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = ["arn:aws:logs:ap-northeast-2:723165663216:log-group:/aws/kinesisfirehose/*:log-stream:*"]
      },
    ]
  })

  # 콘솔 기본 템플릿 (떼어진 쪽). S3 문장만 전용 버킷, 나머지(Glue·Kafka·Lambda·KMS·Kinesis)는 쓰지 않는 빈 자리(PLACEHOLDER).
  firehose_template_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Action = ["glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"]
        Resource = [
          "arn:aws:glue:ap-northeast-2:723165663216:catalog",
          "arn:aws:glue:ap-northeast-2:723165663216:database/${local.firehose_placeholder}",
          "arn:aws:glue:ap-northeast-2:723165663216:table/${local.firehose_placeholder}/${local.firehose_placeholder}",
        ]
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = ["kafka:GetBootstrapBrokers", "kafka:DescribeCluster", "kafka:DescribeClusterV2", "kafka-cluster:Connect"]
        Resource = "arn:aws:kafka:ap-northeast-2:723165663216:cluster/${local.firehose_placeholder}/${local.firehose_placeholder}"
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeTopic", "kafka-cluster:DescribeTopicDynamicConfiguration", "kafka-cluster:ReadData"]
        Resource = "arn:aws:kafka:ap-northeast-2:723165663216:topic/${local.firehose_placeholder}/${local.firehose_placeholder}/${local.firehose_placeholder}"
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeGroup"]
        Resource = "arn:aws:kafka:ap-northeast-2:723165663216:group/${local.firehose_placeholder}/${local.firehose_placeholder}/*"
      },
      {
        Sid    = ""
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject",
          "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject",
        ]
        Resource = [aws_s3_bucket.rds_audit.arn, "${aws_s3_bucket.rds_audit.arn}/*"]
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
        Resource = "arn:aws:lambda:ap-northeast-2:723165663216:function:${local.firehose_placeholder}"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = ["arn:aws:kms:ap-northeast-2:723165663216:key/${local.firehose_placeholder}"]
        Condition = {
          StringEquals = { "kms:ViaService" = "s3.ap-northeast-2.amazonaws.com" }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [
              "arn:aws:s3:::${local.firehose_placeholder}/*",
              "arn:aws:s3:::${local.firehose_placeholder}",
            ]
          }
        }
      },
      {
        Sid    = ""
        Effect = "Allow"
        Action = ["logs:PutLogEvents"]
        Resource = [
          "${aws_cloudwatch_log_group.firehose_rds_audit.arn}:log-stream:*",
          "arn:aws:logs:ap-northeast-2:723165663216:log-group:${local.firehose_placeholder}:log-stream:*",
        ]
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
        Resource = "arn:aws:kinesis:ap-northeast-2:723165663216:stream/${local.firehose_placeholder}"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["arn:aws:kms:ap-northeast-2:723165663216:key/${local.firehose_placeholder}"]
        Condition = {
          StringEquals = { "kms:ViaService" = "kinesis.ap-northeast-2.amazonaws.com" }
          StringLike   = { "kms:EncryptionContext:aws:kinesis:arn" = "arn:aws:kinesis:ap-northeast-2:723165663216:stream/${local.firehose_placeholder}" }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "firehose_rds_audit" {
  for_each = local.firehose_rds_audit_policies

  name   = "KinesisFirehoseServicePolicy-RDS-Audit-PUT-S3-ap-northeast-2${each.value.name_suffix}"
  path   = "/service-role/"
  policy = each.value.policy
}

# 역할에 붙은 건 -alt 하나 (central_logs 는 2026-09-24 22:52 뗌).
resource "aws_iam_role_policy_attachment" "firehose_rds_audit" {
  for_each = { for k, v in aws_iam_policy.firehose_rds_audit : k => v if k == "rds_audit" }

  role       = aws_iam_role.firehose_rds_audit.name
  policy_arn = each.value.arn
}

# CloudWatch Logs → Firehose 역할 — 감사 로그 그룹의 구독 필터(storage.tf rds_audit)가 Firehose 에 넣을 때 쓴다.
# 2026-09-24 23:44 KST jaewoon 콘솔 생성 (22:18·22:38 실패는 Firehose 서비스 역할을 넣어서였다), 신뢰 정책 00:29 수정.
resource "aws_iam_role" "logs_to_firehose" {
  name                 = "CloudWatchLogsToFirehoseRole"
  description          = ""
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.ap-northeast-2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "logs_to_firehose" {
  name = "CloudWatchLogsToFirehoseRolePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "firehose:PutRecord"
      Resource  = aws_kinesis_firehose_delivery_stream.rds_audit.arn
      Condition = { StringEquals = { "aws:ResourceAccount" = "723165663216" } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs_to_firehose" {
  role       = aws_iam_role.logs_to_firehose.name
  policy_arn = aws_iam_policy.logs_to_firehose.arn
}

# AWS Backup 기본 서비스 역할 — 2026-09-25 16:06 KST jaewoon 이 백업 계획(database.tf aws_backup_selection.rds)을 만들 때 콘솔이 생성.
resource "aws_iam_role" "backup" {
  name                 = "AWSBackupDefaultServiceRole"
  path                 = "/service-role/"
  description          = "Provides AWS Backup permission to create backups and perform restores on your behalf across AWS services"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}
