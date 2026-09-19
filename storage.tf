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
