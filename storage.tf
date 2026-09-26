# 스토리지 · 로그 — 정적 자원 버킷(CloudFront OAC 전용), 로그 버킷 3개(중앙 = CloudFront + ALB · WAF · CloudTrail) + 정책·수명주기, CloudWatch 로그 그룹 11개(web 4 + 베스천 1 + RDS 3 + WAS 3).

resource "aws_s3_bucket" "static" {
  bucket = "mc-static-image"
}

# 퍼블릭 액세스 전면 차단 — 접근은 CloudFront OAC 로만.
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront 분포에서 오는 GetObject 만 허용.
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.static.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.main.arn }
      }
    }]
  })
}

# --- CloudWatch 로그 그룹 ---
# 이름 규칙(2026-09-21 결정): /petclinic/<환경>/<계층>/<소스>/<종류>. 태그 Tier 로 계층 구분.
# IA(Infrequent Access)는 저장 단가가 절반이지만 지표 필터·구독·S3 내보내기가 안 된다. 2026-09-22 jaewoon(로그 담당)이 IA 그룹 3개를
# 삭제 — 지금은 전부 STANDARD (에이전트가 만들 때의 기본값).
# 2026-09-23 web v10 부터 보존기간은 에이전트 설정의 retention_in_days 가 건다 — 그룹이 없으면 그 값으로 만들고, 있으면 그 값으로 맞춘다.
# 그래서 미리 만들 필요가 없고 지워져도 같은 보존기간으로 다시 생긴다. 태그만은 에이전트가 못 붙여 콘솔에서 붙인다.
# Apache access 로그의 S3 장기 보관은 하지 않는다 — 같은 요청이 ALB 액세스 로그·CloudFront 로그로 이미 S3 에 남는다.

# (옛 이름 /petclinic/web/{access,error} 는 LT v6 가 쓰던 것 — 2026-09-22 14:33 v7 리프레시와 함께 삭제. 코드·state 에서 제거.)

# web 4개 — userdata/web-v10.sh 의 log_group_name·retention_in_days 와 같아야 한다 (다르면 에이전트가 콘솔 값을 되돌린다).
# apache/access: 9/22 17:54 jaewoon 이 IA 그룹을 삭제 → 9/23 11:15 web 에이전트가 자동 재생성(무기한) → 14:15 v9 에이전트가 30일로 맞춤.
# 태그 Tier=WEB 은 아직 없음 — jaewoon 이 콘솔에서 붙이면 tags 추가 (지금 코드에 두면 plan 에 변경 1건이 생긴다).
resource "aws_cloudwatch_log_group" "web_apache_access" {
  name              = "/petclinic/prod/web/apache/access"
  retention_in_days = 30
  log_group_class   = "STANDARD"
}

resource "aws_cloudwatch_log_group" "web_apache_error" {
  name              = "/petclinic/prod/web/apache/error"
  retention_in_days = 90
  log_group_class   = "STANDARD" # 5xx·프록시 오류 지표 필터 대상

  tags = {
    Tier = "WEB"
  }
}


# SSH 로그인 이력(/var/log/secure). 9/22 17:54 jaewoon 이 IA 그룹을 삭제 → 9/23 14:15 v9 에이전트가 90일로 자동 생성. 태그는 apache/access 와 같이 아직 없음.
resource "aws_cloudwatch_log_group" "web_ssh_access" {
  name              = "/petclinic/prod/web/ssh/access"
  retention_in_days = 90
  log_group_class   = "STANDARD"
}

resource "aws_cloudwatch_log_group" "web_bootstrap" {
  name              = "/petclinic/prod/web/bootstrap"
  retention_in_days = 14
  log_group_class   = "STANDARD"

  tags = {
    Tier = "WEB"
  }
}

# 베스천 SSH 로그인 이력 (2026-09-22 콘솔 생성). 22 가 전체 개방이라 실패 시도 지표 필터를 걸 수 있게 STANDARD.
resource "aws_cloudwatch_log_group" "bastion_ssh_secure" {
  name              = "/petclinic/prod/bastion/ssh/secure"
  retention_in_days = 90
  log_group_class   = "STANDARD"

  tags = {
    Tier = "BASTION"
  }
}


# RDS error·slowquery — 2026-09-25 00:58·01:01 KST jaewoon 이 보존 30일로 바꿈 (그 전엔 0 = 만료 안 됨).
# (/aws/rds/proxy/pet-proxy 는 프록시와 함께 2026-09-22 삭제)
resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/database-1/error"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/instance/database-1/slowquery"
  retention_in_days = 30
}

# 감사 로그 — 2026-09-24 14:56 옵션 그룹 연결 때 RDS 가 자동 생성(무기한), 16:20 KST jaewoon 이 30일로 줄임 (모든 쿼리가 남아 양이 많다).
resource "aws_cloudwatch_log_group" "rds_audit" {
  name              = "/aws/rds/instance/database-1/audit"
  retention_in_days = 30
}

# 감사 로그 → Firehose RDS-Audit-PUT-S3 → 전용 버킷. 2026-09-24 23:44 KST jaewoon 콘솔 생성 (역할 iam.tf logs_to_firehose).
# ⚠️ 2026-09-25 00:56 RDS 의 audit 로그 내보내기를 꺼서(database.tf) 지금은 이 그룹에 새 로그가 안 들어온다 → 파이프라인은 대기 상태.
resource "aws_cloudwatch_log_subscription_filter" "rds_audit" {
  name            = "rds-audit"
  log_group_name  = aws_cloudwatch_log_group.rds_audit.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.rds_audit.arn
  role_arn        = aws_iam_role.logs_to_firehose.arn
  distribution    = "ByLogStream"
}

# Firehose RDS-Audit-PUT-S3(monitoring.tf) 의 전송 오류 로그 — 2026-09-24 20:40 KST jaewoon 이 Firehose 를 만들 때 콘솔이 생성(무기한).
# 스트림 DestinationDelivery·BackupDelivery 도 콘솔이 함께 만든 것이라 코드로 관리하지 않는다.
resource "aws_cloudwatch_log_group" "firehose_rds_audit" {
  name              = "/aws/kinesisfirehose/RDS-Audit-PUT-S3"
  retention_in_days = 0
  log_group_class   = "STANDARD"
}

# WAS 3개 — 2026-09-23 23:31 KST WAS 의 CloudWatch Agent 가 자동 생성 (semin 이 23:30 역할에 에이전트 정책을 붙인 직후).
# 에이전트 설정(Parameter Store /petclinic/cwagent/was)에 보존기간이 없어 무기한. 태그 없음.
resource "aws_cloudwatch_log_group" "was_application" {
  name              = "/petclinic/prod/was/petclinic/application"
  retention_in_days = 0
  log_group_class   = "STANDARD"
}

resource "aws_cloudwatch_log_group" "was_tomcat_access" {
  name              = "/petclinic/prod/was/tomcat/access"
  retention_in_days = 0
  log_group_class   = "STANDARD"
}

resource "aws_cloudwatch_log_group" "was_tomcat_catalina" {
  name              = "/petclinic/prod/was/tomcat/catalina"
  retention_in_days = 0
  log_group_class   = "STANDARD"
}

# (ALB 전용 로그 버킷 petclinic-log-alb 는 2026-09-22 16:23 삭제 — ALB 로그는 아래 중앙 버킷 petclinic/prod/entry/ 로 이동.)

# 2026-09-21: 버전 관리 + 이전 버전 30일 보관 — 정적 파일을 잘못 지우거나 덮어써도 되살릴 수 있게 (그동안 두 번 사고).
resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    id     = "expire-old-versions-30d"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# --- 중앙 로그 버킷 (2026-09-21 콘솔 생성) — S3 로그의 한 지붕 ---
#   petclinic/prod/edge/cloudfront/access/year=…   CloudFront 표준 로그 v2 (yena 9/21, edge.tf 의 log delivery 3종, Hive 경로)
#   petclinic/prod/entry/alb/{public,internal}/AWSLogs/…   ALB 액세스 로그 (9/22 16:21 전용 버킷에서 이동; ALB 는 AWSLogs/… 를 스스로 붙임)
# WAF 로그만 별도 버킷 — AWS 규칙상 버킷 이름이 aws-waf-logs- 로 시작해야 해서.
# 정책 = CloudFront 전송용 2문장(콘솔 자동) + ELB 서비스·서울 ELB 계정(600734575887) 쓰기 2문장. 수명주기는 접두사별.
resource "aws_s3_bucket" "central_logs" {
  bucket = "mc-logs-petclinic"
}

resource "aws_s3_bucket_policy" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AWSLogDeliveryWrite20150319"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite1"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.central_logs.arn}/AWSLogs/aws-account-id=723165663216/CloudFront/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = "723165663216" }
          ArnLike      = { "aws:SourceArn" = aws_cloudwatch_log_delivery_source.cloudfront_access.arn }
        }
      },
      {
        Sid       = "AWSLogDeliveryWrite2"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.central_logs.arn}/petclinic/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = "723165663216" }
          ArnLike      = { "aws:SourceArn" = aws_cloudwatch_log_delivery_source.cloudfront_access.arn }
        }
      },
      {
        Sid       = "AllowELBLogDeliveryService"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.central_logs.arn}/petclinic/prod/entry/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AllowELBLogDeliveryAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::600734575887:root" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.central_logs.arn}/petclinic/prod/entry/*"
      },
    ]
  })
}

# 접두사별 보존: entry(ALB) 90일 · edge(CloudFront) 14일.
resource "aws_s3_bucket_lifecycle_configuration" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  rule {
    id     = "expire-entry-90d"
    status = "Enabled"

    filter {
      prefix = "petclinic/prod/entry/"
    }

    expiration {
      days = 90
    }
  }

  # 2026-09-24 17:38 KST yena 콘솔 추가. 멀티파트 업로드 조각도 7일 뒤 정리.
  rule {
    id     = "Delete-CF-Logs-After-14-Days"
    status = "Enabled"

    filter {
      prefix = "petclinic/prod/edge/"
    }

    expiration {
      days = 14
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- WAF 로그 버킷 (2026-09-21 콘솔 생성, us-east-1) ---
# CloudFront 용 web ACL 은 us-east-1 에 있어 로그 버킷도 거기 만들었고, 이름은 WAF 규칙대로 aws-waf-logs- 접두사.
# 2026-09-21 15:42 KST yena 가 web ACL 로깅을 켜 `AWSLogs/723165663216/WAFLogs/cloudfront/…` 로 쌓인다 (edge.tf 로깅 설정 참고).
# 버킷 정책은 로깅 설정 시 콘솔이 자동 생성(delivery.logs 서비스). 수명주기 없음.
resource "aws_s3_bucket" "waf_logs" {
  provider = aws.us_east_1
  bucket   = "aws-waf-logs-petclinic-block"
}

resource "aws_s3_bucket_policy" "waf_logs" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.waf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AWSLogDeliveryWrite20150319"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite1"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/723165663216/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = "723165663216" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:logs:us-east-1:723165663216:*" }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck1"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.waf_logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = "723165663216" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:logs:us-east-1:723165663216:*" }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CloudTrail 버킷 (2026-09-23 22:08 KST jaewoon 콘솔 생성) — 트레일 cloud-logs-all(monitoring.tf) 전용 ---
# 정책 2문장은 트레일 만들 때 콘솔이 자동으로 넣은 것(Sid 의 UUID 포함 그대로). 수명주기 없음 = 로그 무기한 보관.
# 객체 소유권 BucketOwnerEnforced(ACL 끔)·SSE-C 차단은 콘솔 기본값이라 코드에 두지 않는다.
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "bespin-cloudtrail-logs"
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck20150319-7dfabc2a-8080-4a5d-b261-fda9a5e58256"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = { "AWS:SourceArn" = "arn:aws:cloudtrail:ap-northeast-2:723165663216:trail/cloud-logs-all" }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite20150319-a0e7310e-ec54-4e16-b8d6-64ebf64e1229"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/723165663216/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:ap-northeast-2:723165663216:trail/cloud-logs-all"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- RDS 감사 로그 버킷 (2026-09-24 21:23 KST jaewoon 콘솔 생성) — Firehose RDS-Audit-PUT-S3(monitoring.tf) 전용 ---
# 버킷 정책 없음 — Firehose 역할(iam.tf)의 권한으로 쓴다. 버전 관리 없음.
# 수명주기(21:59 추가): rds/audit/ 30일 뒤 Glacier Instant Retrieval, 335일 뒤 삭제.
# 객체 소유권 BucketOwnerEnforced·SSE-C 차단은 콘솔 기본값이라 코드에 두지 않는다.
resource "aws_s3_bucket" "rds_audit" {
  bucket = "rds-audit-bespin-723165663216-ap-northeast-2-an"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rds_audit" {
  bucket = aws_s3_bucket.rds_audit.id

  rule {
    bucket_key_enabled = false
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "rds_audit" {
  bucket = aws_s3_bucket.rds_audit.id

  rule {
    id     = "rds-audit-335days"
    status = "Enabled"

    filter {
      prefix = "rds/audit/"
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 335
    }
  }
}

resource "aws_s3_bucket_public_access_block" "rds_audit" {
  bucket = aws_s3_bucket.rds_audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
