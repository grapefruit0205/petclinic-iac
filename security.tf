# 보안 그룹 7개(eice-sg 포함) — 규칙은 인라인 블록 (import 시 provider 가 읽어 오는 형태 그대로).
# 규칙 묶음(블록) 단위는 실물의 IpPermissions 그룹과 1:1 이어야 plan 이 0 이다.
# `default` SG 는 VPC 기본이라 관리 대상에서 뺐다 (data.tf 에서 조회만).

# 베스천. ⚠️ 22 뿐 아니라 80·443 도 0.0.0.0/0 에 열려 있다.
resource "aws_security_group" "bastion" {
  name        = "SG-bastion"
  description = "SSH allow"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public ALB. 80·443 전체 개방 → CloudFront·WAF 를 우회해 ALB 로 직접 접근 가능.
# 22 ← bastion 규칙은 ALB 에 의미가 없지만 실물에 있어 유지.
resource "aws_security_group" "alb_public" {
  name        = "alb-public-sg"
  description = "alb allow"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internal ALB. web 인스턴스(httpd 리버스프록시)에서만 80·8080.
resource "aws_security_group" "alb_internal" {
  name        = "alb-internal-sg"
  description = "petclinic 8080 port allow"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# web 인스턴스 (ASG web-test · WEB-test-a · web-ami). 0.0.0.0/0 규칙 없음.
resource "aws_security_group" "web" {
  name        = "web-instance-sg"
  description = "web allow"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description     = "alb-public-sg"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }
  ingress {
    description     = "ssh"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  # 2026-09-21: EC2 Instance Connect Endpoint 경유 SSH (부가 경로). 베스천은 유지하므로 위의 bastion 참조 블록도 그대로 둔다.
  ingress {
    description     = "eice"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# WAS 인스턴스. ⚠️ 80·443·8080 이 0.0.0.0/0 에 열려 있다 (설명은 "alb-internal-sg" 지만 소스는 전체).
# 프라이빗 서브넷이라 인터넷에서 직접 닿지는 않지만 VPC 안 어디서든 접근 가능.
resource "aws_security_group" "was" {
  name        = "was-instance-sg"
  description = "was allow"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description = "alb-internal-sg"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssm"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  # EICE 로 WAS 에 들어가려면 여기에 22 ← aws_security_group.eice 규칙이 필요하다 — WAS 담당이 넣기로 하고 2026-09-21 테스트 규칙은 회수했다.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS · RDS Proxy 공용. 3306 ← was-instance-sg, 3306 ← 자기 자신(프록시 ↔ DB).
resource "aws_security_group" "db" {
  name        = "petclinic-db-sg"
  description = "HIBYE"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.was.id]
    self            = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance Connect Endpoint 전용 (2026-09-21). 인바운드 없음, 아웃바운드는 VPC 안 22 만.
# web SG 의 "22 ← eice" 규칙이 이 SG 를 소스로 참조한다 (베스천 SG 참조와 병행).
resource "aws_security_group" "eice" {
  name        = "eice-sg"
  description = "EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "eice-sg"
  }
}
