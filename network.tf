# 네트워크 계층 — 콘솔에서 만든 실물을 import 로 연결한 resource 블록.
# 값은 2026-09-19 실측. 속성을 바꾸면 apply 가 실물을 바꾼다.

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    Name = "test-vpc"
  }
}

# --- 서브넷: public 2 · web 2 · was 2 · db 2 (2a / 2c) ---
resource "aws_subnet" "public1_2a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false # 퍼블릭 서브넷이지만 자동 퍼블릭 IP 는 꺼져 있음 (bastion·web-ami 는 시작 시 수동 지정)

  tags = {
    Name = "test-subnet-public1-ap-northeast-2a"
  }
}

resource "aws_subnet" "public2_2c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-public2-ap-northeast-2c"
  }
}

# web 계층 (ASG web-test · WEB-test-a · internal ALB)
resource "aws_subnet" "private1_2a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private1-ap-northeast-2a"
  }
}

resource "aws_subnet" "private2_2c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private2-ap-northeast-2c"
  }
}

# WAS 계층 (WAS-test-a)
resource "aws_subnet" "private3_2a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private3-ap-northeast-2a"
  }
}

resource "aws_subnet" "private4_2c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.21.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private4-ap-northeast-2c"
  }
}

# DB 계층 (RDS · RDS Proxy)
resource "aws_subnet" "private5_2a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.30.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private5-ap-northeast-2a"
  }
}

resource "aws_subnet" "private6_2c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.31.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name = "test-subnet-private6-ap-northeast-2c"
  }
}

# --- 인터넷 게이트웨이 · NAT ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "test-igw"
  }
}

# NAT 용 EIP 2개. (Public ALB 에 붙은 EIP 2개는 ELB 가 관리하므로 코드에 두지 않는다)
resource "aws_eip" "nat_2a" {
  domain = "vpc"

  tags = {
    Name = "test-eip-ap-northeast-2a"
  }
}

resource "aws_eip" "nat_2c" {
  domain = "vpc"

  tags = {
    Name = "test-eip-ap-northeast-2c"
  }
}

resource "aws_nat_gateway" "public1_2a" {
  subnet_id         = aws_subnet.public1_2a.id
  allocation_id     = aws_eip.nat_2a.id
  connectivity_type = "public"

  tags = {
    Name = "test-nat-public1-ap-northeast-2a"
  }
}

resource "aws_nat_gateway" "public2_2c" {
  subnet_id         = aws_subnet.public2_2c.id
  allocation_id     = aws_eip.nat_2c.id
  connectivity_type = "public"

  tags = {
    Name = "test-nat-public2-ap-northeast-2c"
  }
}

# --- 라우트 테이블 ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "test-rtb-public"
  }
}

# 2a 쪽 web·was 서브넷 → 2a NAT
resource "aws_route_table" "private1_2a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public1_2a.id
  }

  tags = {
    Name = "test-rtb-private1-ap-northeast-2a"
  }
}

# 2c 쪽 web·was 서브넷 → 2c NAT
resource "aws_route_table" "private2_2c" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public2_2c.id
  }

  tags = {
    Name = "test-rtb-private2-ap-northeast-2c"
  }
}

# 2a DB 서브넷 → 2a NAT
resource "aws_route_table" "private3_2a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public1_2a.id
  }

  tags = {
    Name = "test-rtb-private3-ap-northeast-2a"
  }
}

# 2c DB 서브넷 → 2c NAT
resource "aws_route_table" "private4_2c" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public2_2c.id
  }

  tags = {
    Name = "test-rtb-private4-ap-northeast-2c"
  }
}

# VPC 기본(main) 라우트 테이블 — 서브넷 연결 없음, local 라우트만. import ID 는 VPC ID.
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id
}

# --- 서브넷 ↔ 라우트 테이블 연결 ---
resource "aws_route_table_association" "public1_2a" {
  subnet_id      = aws_subnet.public1_2a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2_2c" {
  subnet_id      = aws_subnet.public2_2c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1_2a" {
  subnet_id      = aws_subnet.private1_2a.id
  route_table_id = aws_route_table.private1_2a.id
}

resource "aws_route_table_association" "private3_2a" {
  subnet_id      = aws_subnet.private3_2a.id
  route_table_id = aws_route_table.private1_2a.id
}

resource "aws_route_table_association" "private2_2c" {
  subnet_id      = aws_subnet.private2_2c.id
  route_table_id = aws_route_table.private2_2c.id
}

resource "aws_route_table_association" "private4_2c" {
  subnet_id      = aws_subnet.private4_2c.id
  route_table_id = aws_route_table.private2_2c.id
}

resource "aws_route_table_association" "private5_2a" {
  subnet_id      = aws_subnet.private5_2a.id
  route_table_id = aws_route_table.private3_2a.id
}

resource "aws_route_table_association" "private6_2c" {
  subnet_id      = aws_subnet.private6_2c.id
  route_table_id = aws_route_table.private4_2c.id
}
