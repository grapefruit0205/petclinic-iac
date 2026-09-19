# 조회 전용 data 소스. resource 블록은 없다 — apply 해도 아무것도 만들지 않는다.

# --- 엣지 계층 ---
# 3티어 진입점. 오리진·캐시 동작은 이 데이터 소스가 노출하지 않는다 (도메인·별칭·상태만).
data "aws_cloudfront_distribution" "main" {
  id = var.cloudfront_distribution_id
}

# --- 네트워크 ---
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnet" "named" {
  for_each = toset(var.subnet_names)

  filter {
    name   = "tag:Name"
    values = [each.value]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

data "aws_internet_gateway" "main" {
  internet_gateway_id = var.internet_gateway_id
}

data "aws_nat_gateway" "named" {
  for_each = toset(var.nat_gateway_ids)
  id       = each.value
}

data "aws_route_table" "named" {
  for_each       = toset(var.route_table_ids)
  route_table_id = each.value
}

# 주의: 이 엔드포인트는 사용자가 만든 것이 아니라 RDS Proxy(pet-proxy) 가 자동 생성한 AWS 관리 엔드포인트다
# (서비스 owner amazon, ManagesVpcEndpoints=true, DB 서브넷 · petclinic-db-sg). 조회만 하고 import 대상에서는 뺐다.
data "aws_vpc_endpoint" "main" {
  id = var.vpc_endpoint_id
}

# --- 진입 계층 ---
data "aws_lb" "named" {
  for_each = toset(var.alb_names)
  name     = each.value
}

data "aws_lb_target_group" "named" {
  for_each = toset(var.target_group_names)
  name     = each.value
}

# --- 컴퓨트 계층 ---
data "aws_autoscaling_group" "web" {
  name = var.asg_name
}

# ASG 가 띄운 인스턴스 (aws_autoscaling_group 데이터 소스에는 instances 속성이 없다)
data "aws_instances" "asg" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [var.asg_name]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_launch_template" "web" {
  name = var.launch_template_name
}

data "aws_instance" "named" {
  for_each = toset(var.instance_names)

  filter {
    name   = "tag:Name"
    values = [each.value]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_security_group" "named" {
  for_each = toset(var.security_group_names)

  name   = each.value
  vpc_id = data.aws_vpc.main.id
}

data "aws_iam_role" "ec2" {
  name = var.iam_role_name
}

data "aws_iam_instance_profile" "named" {
  for_each = toset(var.instance_profile_names)
  name     = each.value
}

# --- 데이터 계층 ---
data "aws_db_instance" "main" {
  db_instance_identifier = var.db_identifier
}

data "aws_db_proxy" "main" {
  name = var.db_proxy_name
}

data "aws_db_subnet_group" "main" {
  name = var.db_subnet_group_name
}

# --- 스토리지 · 로그 ---
data "aws_s3_bucket" "static" {
  bucket = var.s3_bucket_name
}

# 버킷에 붙은 정책 문서 (CloudFront OAC 접근 허용). 정책이 없으면 조회가 실패한다.
data "aws_s3_bucket_policy" "static" {
  bucket = var.s3_bucket_name
}

data "aws_cloudwatch_log_group" "named" {
  for_each = toset(var.log_group_names)
  name     = each.value
}