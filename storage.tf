# 스토리지 · 로그 — 정적 자원 버킷(CloudFront OAC 전용), 로그 버킷 3개(ALB · 중앙 로그(CloudFront) · WAF) + 정책, CloudWatch 로그 그룹 4개.

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
# web 인스턴스의 CloudWatch Agent 가 쓴다 (userdata/web.sh).
resource "aws_cloudwatch_log_group" "web_access" {
  name              = "/petclinic/web/access"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "web_error" {
  name              = "/petclinic/web/error"
  retention_in_days = 90
}

# RDS 쪽 2개는 보존기간 없음(0 = 만료 안 됨). (/aws/rds/proxy/pet-proxy 는 프록시와 함께 2026-09-22 삭제)
resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/database-1/error"
  retention_in_days = 0
}

resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/instance/database-1/slowquery"
  retention_in_days = 0
}

# --- ALB 액세스 로그 버킷 (2026-09-21 콘솔 생성, Phase 1-A) ---
# Public·Internal ALB 가 요청 단위 로그(경로·응답시간·타깃·코드)를 gzip 으로 쓴다. 90일 뒤 만료.
# 정책은 서울 리전 ELB 로그 계정(600734575887)과 logdelivery 서비스 둘 다 허용 — 콘솔이 만든 그대로.
resource "aws_s3_bucket" "alb_logs" {
  bucket = "petclinic-log-alb"
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBLogDeliveryService"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AllowELBLogDeliveryAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::600734575887:root" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/*"
      },
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-90d"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

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

# --- 중앙 로그 버킷 (2026-09-21 콘솔 생성) ---
# 2026-09-21 18:06~18:31 KST yena: CloudFront 표준 로그(v2) 목적지로 사용 시작 — edge.tf 의 log delivery 3종이
# `petclinic/prod/edge/cloudfront/access/{yyyy}/{MM}/{dd}/{HH}` 로 쓴다. 버킷 정책은 콘솔이 자동 생성한 것(delivery.logs 서비스).
# 수명주기 없음(로그가 무한히 쌓인다 — 보존 기간 정하면 lifecycle 추가). CloudWatch Logs → S3 내보내기(Phase 2) 목적지도 겸할 예정.
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
    ]
  })
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
