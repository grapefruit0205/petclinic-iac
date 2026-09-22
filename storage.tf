# 스토리지 · 로그 — 정적 자원 버킷(CloudFront OAC 전용), 로그 버킷 2개(중앙 = CloudFront + ALB · WAF) + 정책·수명주기, CloudWatch 로그 그룹 8개(web 4 + 베스천 2 + RDS 2).

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
# 이름 규칙(2026-09-21 결정): /petclinic/<환경>/<계층>/<소스>/<종류>. 클래스는 생성 후 못 바꾸므로 에이전트 기동 전에 CLI 로 만든다.
# IA(Infrequent Access)는 저장 단가가 절반이지만 지표 필터·구독·S3 내보내기가 안 된다 → 알람을 걸 error 계열만 STANDARD.
# Apache access 로그의 S3 장기 보관은 하지 않는다 — 같은 요청이 ALB 액세스 로그·CloudFront 로그로 이미 S3 에 남는다. 태그 Tier 로 계층 구분.

# (옛 이름 /petclinic/web/{access,error} 는 LT v6 가 쓰던 것 — 2026-09-22 14:33 v7 리프레시와 함께 삭제. 코드·state 에서 제거.)

# web v7 용 4개 (2026-09-22 생성, userdata/web-v7.sh 의 log_group_name 과 글자 단위로 같아야 한다). 14:34 리프레시 뒤 v7 2대가 쓰는 중.
resource "aws_cloudwatch_log_group" "web_apache_access" {
  name              = "/petclinic/prod/web/apache/access"
  retention_in_days = 30
  log_group_class   = "INFREQUENT_ACCESS" # 양이 가장 많고 조회만 함

  tags = {
    Tier = "WEB"
  }
}

resource "aws_cloudwatch_log_group" "web_apache_error" {
  name              = "/petclinic/prod/web/apache/error"
  retention_in_days = 90
  log_group_class   = "STANDARD" # 5xx·프록시 오류 지표 필터 대상

  tags = {
    Tier = "WEB"
  }
}

resource "aws_cloudwatch_log_group" "web_ssh_access" {
  name              = "/petclinic/prod/web/ssh/access"
  retention_in_days = 90
  log_group_class   = "INFREQUENT_ACCESS"

  tags = {
    Tier = "WEB"
  }
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

# 베스천 /var/log/messages 용 (2026-09-22 베스천 안에서 생성). 에이전트 설정(cw-bastion.json)엔 아직 안 넣어 비어 있다 —
# 시스템 이상(디스크·OOM)은 지표로 보고 있어 선택 사항. 쓰려면 userdata/bastion-cwagent.sh 의 collect_list 에 추가 후 fetch-config.
resource "aws_cloudwatch_log_group" "bastion_system_messages" {
  name              = "/petclinic/prod/bastion/system/messages"
  retention_in_days = 14
  log_group_class   = "INFREQUENT_ACCESS"

  tags = {
    Tier = "BASTION"
  }
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

# 접두사별 보존. edge(CloudFront) 쪽 규칙은 아직 콘솔에서 안 만듦 — 만들면 여기 rule 추가 + plan.
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
