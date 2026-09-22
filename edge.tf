# 엣지 계층 — Route53 → CloudFront(WAF) → Public ALB / S3.
# WAF 웹 ACL 과 CloudFront 뷰어 인증서는 us-east-1 (provider alias).

resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "mc-static-image.s3.ap-northeast-2.amazonaws.com"
  description                       = "" # provider 기본값 "Managed by Terraform" 을 비워 실물과 맞춤
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront 뷰어 인증서 (us-east-1). ALB 용은 entry.tf.
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = "*.mission-critical.site"
  subject_alternative_names = ["*.mission-critical.site"]
  validation_method         = "DNS"
  key_algorithm             = "RSA_2048"
}

# CloudFront 콘솔이 만든 웹 ACL. ⚠️ 관리형 룰 4개 전부 Count (차단 없음), 로깅 없음.  (rule4 = SQLi, none)
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1

  name  = "CreatedByCloudFront-2407cc5b"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 4번째 룰만 none — 앞의 3개는 Count 라 탐지만 하고 차단하지 않는다.
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CreatedByCloudFront-2407cc5b"
    sampled_requests_enabled   = true
  }
}

# WAR 메뉴의 HOME/로고가 가리키는 /petclinic/ (옛 홈)을 S3 랜딩(/)으로 302 돌려보내는 뷰어 요청 함수.
# 302(임시)라서 리디자인 WAR 를 배포한 뒤 연결만 떼면 원래대로 돌아온다. 코드는 콘솔에 게시된 LIVE 원문 그대로.
resource "aws_cloudfront_function" "home_to_landing" {
  name    = "petclinic-home-to-landing"
  runtime = "cloudfront-js-2.0"
  comment = ""
  publish = true
  code    = file("${path.module}/cloudfront/petclinic-home-to-landing.js")

  # publish 는 API 가 아닌 Terraform 전용 인자라 import 로 state 에 들어오지 않는다 (ASG 의 force_delete 등과 같은 경우).
  # 코드 변경은 콘솔에서 하고 여기엔 LIVE 원문을 복사하는 운영이라 무시해도 된다.
  lifecycle {
    ignore_changes = [publish]
  }
}

# 오리진 2개 · 동작 3개 (2026-09-19 21:00 KST 콘솔 변경 반영):
#   기본(*)                → S3  랜딩 사이트 (index.html · css/ · images/), CachingOptimized
#   /petclinic/resources/* → S3  WAR 페이지가 쓰는 css·이미지, CachingOptimized
#   /petclinic/*           → ALB 동적 앱, CachingDisabled + AllViewer (헤더·쿠키·쿼리스트링 전부 오리진으로)
# /petclinic/* 를 AllViewer 로 두기 전엔 쿼리스트링이 잘려 보호자 검색(?lastName=)이 동작하지 않았다.
# 직접 d3q5zkso8oivib.cloudfront.net 으로 오면 Host 가 ALB 인증서(*.mission-critical.site)와 안 맞아 502 — 별칭으로만 동작.
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"
  aliases             = ["24petclinic.mission-critical.site"]
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    origin_id   = "test-Public-ALB-1734796970.ap-northeast-2.elb.amazonaws.com-mu55v3ecfl1"
    domain_name = aws_lb.public.dns_name

    # ALB 쪽에서 이 헤더를 검사하는 리스너 규칙은 없다 — 설정만 있고 강제되지 않음.
    custom_header {
      name  = "superheader"
      value = "mypetcliniczzang"
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "mc-static-image.s3.ap-northeast-2.amazonaws.com"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  # 기본: S3 랜딩 사이트. 관리형 캐시 정책 CachingOptimized (658327ea…)
  default_cache_behavior {
    target_origin_id       = "mc-static-image.s3.ap-northeast-2.amazonaws.com"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # ordered_cache_behavior 는 적힌 순서가 우선순위다 — 구체적인 패턴이 먼저 와야 한다.
  ordered_cache_behavior {
    path_pattern           = "/petclinic/resources/*"
    target_origin_id       = "mc-static-image.s3.ap-northeast-2.amazonaws.com"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # 동적 앱. 관리형 CachingDisabled (4135ea2d…) + 오리진 요청 정책 AllViewer (216adef6…)
  ordered_cache_behavior {
    path_pattern             = "/petclinic/*"
    target_origin_id         = "test-Public-ALB-1734796970.ap-northeast-2.elb.amazonaws.com-mu55v3ecfl1"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.home_to_landing.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "mc"
  }
}

# --- Route53 ---
# 도메인 등록은 Route53 Domains 에 없다(외부 등록) — NS 만 이 존으로 위임돼 있다.
resource "aws_route53_zone" "main" {
  name    = "mission-critical.site"
  comment = "" # provider 기본값 "Managed by Terraform" 을 비워 실물과 맞춤
}

resource "aws_route53_record" "app_a" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "24petclinic.mission-critical.site"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app_aaaa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "24petclinic.mission-critical.site"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# ACM DNS 검증 CNAME. 두 인증서(ALB · CloudFront)가 같은 *.mission-critical.site 라 레코드 하나를 공유한다.
resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_4291571fd8079830c5cc27aed5766391.mission-critical.site"
  type    = "CNAME"
  ttl     = 300
  records = ["_55ba0c9baa25f1d0cce6c3cf7a8f0c22.wzccmgtwzk.acm-validations.aws."]
}

# --- 엣지 관측 (2026-09-21 오후·저녁 콘솔, yena) ---
# WAF 로깅: web ACL → S3 aws-waf-logs-petclinic-block. 쿼리스트링과 superheader 값은 로그에서 마스킹.
# 필터 = BLOCK 된 요청만 저장(기본 DROP) — 관리형 룰 3개가 Count 라 실제로 남는 건 SQLi 룰 차단뿐. 15:42~15:44 KST.
resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_s3_bucket.waf_logs.arn]

  redacted_fields {
    query_string {}
  }
  redacted_fields {
    single_header {
      name = "superheader"
    }
  }

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ALL"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }
    }
  }
}

# CloudFront 표준 로그 v2 — 배포 설정(logging_config)이 아니라 CloudWatch Logs "전송(delivery)" 3종으로 구성된다 (us-east-1).
# 소스 = 배포의 ACCESS_LOGS, 목적지 = S3 mc-logs-petclinic/petclinic, 전송 = 필드 33개 · JSON · Hive 경로
# `petclinic/prod/edge/cloudfront/access/year=/month=/day=/hour=`. 18:06 생성 → 18:28 목적지 교체 → 18:31 확정. 이름들은 콘솔 자동 생성.
resource "aws_cloudwatch_log_delivery_source" "cloudfront_access" {
  provider     = aws.us_east_1
  name         = "CreatedByCloudFront-E1F6M0QDUUT8AG-ACCESS_LOGS"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.main.arn
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_access" {
  provider      = aws.us_east_1
  name          = "CF-E1F6M0QDUUT8AG-mc-logs-petclinic-petclinic-1789982984026"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = "${aws_s3_bucket.central_logs.arn}/petclinic"
  }
}

resource "aws_cloudwatch_log_delivery" "cloudfront_access" {
  provider                 = aws.us_east_1
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront_access.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_access.arn

  record_fields = [
    "date", "time", "x-edge-location", "sc-bytes", "c-ip", "cs-method", "cs(Host)", "cs-uri-stem", "sc-status",
    "cs(Referer)", "cs(User-Agent)", "cs-uri-query", "cs(Cookie)", "x-edge-result-type", "x-edge-request-id",
    "x-host-header", "cs-protocol", "cs-bytes", "time-taken", "x-forwarded-for", "ssl-protocol", "ssl-cipher",
    "x-edge-response-result-type", "cs-protocol-version", "fle-status", "fle-encrypted-fields", "c-port",
    "time-to-first-byte", "x-edge-detailed-result-type", "sc-content-type", "sc-content-len", "sc-range-start",
    "sc-range-end",
  ]

  s3_delivery_configuration = [{
    suffix_path                 = "prod/edge/cloudfront/access/{yyyy}/{MM}/{dd}/{HH}"
    enable_hive_compatible_path = true
  }]
}
