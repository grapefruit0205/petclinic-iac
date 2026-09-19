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

# CloudFront 콘솔이 만든 웹 ACL. ⚠️ 관리형 룰 3개 전부 Count (차단 없음), 로깅 없음.
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

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CreatedByCloudFront-2407cc5b"
    sampled_requests_enabled   = true
  }
}

# 오리진 2개: 기본 → Public ALB(https-only, Host 헤더 전달), /petclinic/resources/* → S3(OAC).
# 직접 d3q5zkso8oivib.cloudfront.net 으로 오면 Host 가 ALB 인증서(*.mission-critical.site)와 안 맞아 502 — 별칭으로만 동작.
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_All"
  aliases         = ["24petclinic.mission-critical.site"]
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  origin {
    origin_id   = "test-Public-ALB-1734796970.ap-northeast-2.elb.amazonaws.com-mu55v3ecfl1"
    domain_name = aws_lb.public.dns_name

    # ALB 쪽에서 이 헤더를 검사하는 리스너 규칙은 없다 — 설정만 있고 강제되지 않음.
    custom_header {
      name  = "superheader"
      value = "__CF_SECRET__"
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

  # 관리형 캐시 정책 UseOriginCacheControlHeaders (83da9c7e…): Host·Origin 헤더 + 모든 쿠키가 캐시 키
  default_cache_behavior {
    target_origin_id       = "test-Public-ALB-1734796970.ap-northeast-2.elb.amazonaws.com-mu55v3ecfl1"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "83da9c7e-98b4-4e11-a168-04f0df8e2c65"
  }

  # 관리형 캐시 정책 CachingOptimized (658327ea…)
  ordered_cache_behavior {
    path_pattern           = "/petclinic/resources/*"
    target_origin_id       = "mc-static-image.s3.ap-northeast-2.amazonaws.com"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
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
