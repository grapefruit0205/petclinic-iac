# 스토리지 · 로그 — 정적 자원 버킷(CloudFront OAC 전용) 과 CloudWatch 로그 그룹 5개.
# 계정에 버킷은 이것 하나뿐이라 ALB·CloudFront 로그 버킷은 없다.

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

# RDS 쪽 3개는 보존기간 없음(0 = 만료 안 됨).
resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/database-1/error"
  retention_in_days = 0
}

resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/instance/database-1/slowquery"
  retention_in_days = 0
}

resource "aws_cloudwatch_log_group" "rds_proxy" {
  name              = "/aws/rds/proxy/pet-proxy"
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
