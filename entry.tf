# 진입 계층 — Public ALB(HTTPS·HTTP) → Targetgroup-web, Internal ALB(HTTP) → tg-internal-alb.
# 수동 등록 타깃(WEB-test-a → Targetgroup-web, WAS-test-a → tg-internal-alb)은
# aws_lb_target_group_attachment 가 import 를 지원하지 않아 코드에 없다. ASG 멤버는 ASG 가 등록한다.

resource "aws_lb" "public" {
  name               = "test-Public-ALB"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_public.id]
  subnets            = [aws_subnet.public2_2c.id, aws_subnet.public1_2a.id]

  enable_deletion_protection = false
  idle_timeout               = 60
  enable_http2               = true
  drop_invalid_header_fields = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb/public"
    enabled = true
  }
  connection_logs {
    bucket  = ""
    enabled = false
  }
}

resource "aws_lb" "internal" {
  name               = "alb-internal-test"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.alb_internal.id]
  subnets            = [aws_subnet.private1_2a.id, aws_subnet.private2_2c.id]

  enable_deletion_protection = false
  idle_timeout               = 60
  enable_http2               = true
  drop_invalid_header_fields = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb/internal"
    enabled = true
  }
  connection_logs {
    bucket  = ""
    enabled = false
  }
}

resource "aws_lb_target_group" "web" {
  name        = "Targetgroup-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = "30"

  health_check {
    enabled             = true
    path                = "/health.html"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "was" {
  name        = "tg-internal-alb"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = "30"

  health_check {
    enabled             = true
    path                = "/petclinic/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ALB 리스너용 인증서 (ap-northeast-2). CloudFront 용은 edge.tf 의 us-east-1 인증서.
# DNS 검증 레코드는 edge.tf 의 aws_route53_record.acm_validation (두 인증서가 같은 도메인이라 공유).
resource "aws_acm_certificate" "alb" {
  domain_name               = "*.mission-critical.site"
  subject_alternative_names = ["*.mission-critical.site"]
  validation_method         = "DNS"
  key_algorithm             = "RSA_2048"
}

resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = aws_acm_certificate.alb.arn

  # 2026-09-21 콘솔 변경: 기본 동작을 forward → 403 고정 응답으로. 실제 forward 는 아래 superheader 규칙(우선순위 1)만 한다.
  # → CloudFront 를 안 거친 ALB 직접 접근은 웹 인스턴스에 닿기 전에 ALB 에서 끊긴다 (httpd 의 superheader 검사는 2중 방어로 남는다).
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "403"
    }
  }
}

# 443 의 유일한 규칙: CloudFront 오리진 커스텀 헤더 superheader 가 맞을 때만 Targetgroup-web 으로 forward.
# 값은 edge.tf 의 오리진 커스텀 헤더 · userdata/web.sh 의 CF_SECRET 과 같아야 한다.
resource "aws_lb_listener_rule" "public_https_superheader" {
  listener_arn = aws_lb_listener.public_https.arn
  priority     = 1

  # 리스너 규칙은 provider 가 forward 블록만 읽어 오고 target_group_arn 은 비워 둔다 → forward 블록으로 적어야 plan 이 0.
  # (실물 stickiness duration 이 3600 이라 리스너와 달리 그대로 표현 가능)
  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.web.arn
        weight = 1
      }

      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }

  condition {
    http_header {
      http_header_name = "superheader"
      values           = ["__CF_SECRET__"]
    }
  }
}

# 80 → 443 리다이렉트 (2026-09-21 변경. 그 전엔 forward). CloudFront 는 443 으로만 오고 직접 접근은 어차피 403 이라 실효보다 정리 목적.
resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.was.arn
  }

  # provider 가 default_action.forward 블록(stickiness 포함)을 함께 읽어 오는데, 실물의 stickiness duration 이
  # 0 이라 코드로 표현할 수 없다(허용 범위 1~604800). 단일 타깃 그룹 forward 는 target_group_arn 이 전부이므로 무시한다.
  lifecycle {
    ignore_changes = [default_action[0].forward]
  }
}
