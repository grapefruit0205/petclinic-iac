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

  # 액세스 로그 꺼짐 — 로그 버킷이 없다
  access_logs {
    bucket  = ""
    enabled = false
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
    bucket  = ""
    enabled = false
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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  # provider 가 default_action.forward 블록(stickiness 포함)을 함께 읽어 오는데, 실물의 stickiness duration 이
  # 0 이라 코드로 표현할 수 없다(허용 범위 1~604800). 단일 타깃 그룹 forward 는 target_group_arn 이 전부이므로 무시한다.
  lifecycle {
    ignore_changes = [default_action[0].forward]
  }
}

# 80 은 HTTPS 리다이렉트가 아니라 그대로 forward 다.
resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  # provider 가 default_action.forward 블록(stickiness 포함)을 함께 읽어 오는데, 실물의 stickiness duration 이
  # 0 이라 코드로 표현할 수 없다(허용 범위 1~604800). 단일 타깃 그룹 forward 는 target_group_arn 이 전부이므로 무시한다.
  lifecycle {
    ignore_changes = [default_action[0].forward]
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
