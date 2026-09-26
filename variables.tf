variable "region" {
  description = "AWS region to inspect"
  type        = string
  default     = "ap-northeast-2"
}

# --- 네트워크 ---
variable "vpc_name" {
  description = "Name tag of the VPC"
  type        = string
  default     = "test-vpc"
}

variable "subnet_names" {
  description = "List of subnet Name tags"
  type        = list(string)
  default = [
    "test-subnet-public1-ap-northeast-2a",
    "test-subnet-public2-ap-northeast-2c",
    "test-subnet-private1-ap-northeast-2a",
    "test-subnet-private2-ap-northeast-2c",
    "test-subnet-private3-ap-northeast-2a",
    "test-subnet-private4-ap-northeast-2c",
    "test-subnet-private5-ap-northeast-2a",
    "test-subnet-private6-ap-northeast-2c",
  ]
}

variable "internet_gateway_id" {
  description = "Internet gateway ID"
  type        = string
  default     = "igw-05f4e29cd2ff09752"
}

variable "nat_gateway_ids" {
  description = "NAT gateway IDs"
  type        = list(string)
  default     = ["nat-04c67db946fbf7f5a", "nat-054321cb4593659a4"]
}

variable "route_table_ids" {
  description = "Route table IDs"
  type        = list(string)
  default = [
    "rtb-058eadff3c8ed4570",
    "rtb-0c5562e8a11dc4143",
    "rtb-03ed73d98ca97ee51",
    "rtb-0bf2b5476a7fee7c9",
    "rtb-002a230031020932d",
    "rtb-0e37a33af01492fee",
  ]
}

# --- 진입 계층 ---
variable "alb_names" {
  description = "Load balancer names (public, internal)"
  type        = list(string)
  default     = ["test-Public-ALB", "alb-internal-test"]
}

variable "target_group_names" {
  description = "Target group names"
  type        = list(string)
  default     = ["Targetgroup-web", "tg-internal-alb"]
}

# --- 컴퓨트 계층 ---
variable "asg_name" {
  description = "Auto Scaling group name"
  type        = string
  default     = "web-test"
}

variable "launch_template_name" {
  description = "Launch template name"
  type        = string
  default     = "web"
}

variable "instance_names" {
  description = "Name tags of running standalone instances (ASG members are covered by the ASG lookup). WEB-test-a · web-ami(2026-09-19) · WAS-test-a(2026-09-22) 는 중지돼 조회 목록에서 뺐다 — resource 로는 compute.tf 에서 계속 소유한다. bas-server 는 유지(running)"
  type        = list(string)
  default     = ["bas-server"]
}

variable "security_group_names" {
  description = "Security group GroupName values"
  type        = list(string)
  default = [
    "SG-bastion",
    "alb-internal-sg",
    "alb-public-sg",
    "was-instance-sg",
    "petclinic-db-sg",
    "web-instance-sg",
    "default",
  ]
}

variable "iam_role_name" {
  description = "IAM role used by the EC2 instances"
  type        = string
  default     = "mc-ec2-role"
}

variable "instance_profile_names" {
  description = "Instance profile names"
  type        = list(string)
  default     = ["mc-ec2-role", "was-test-iam"]
}

# --- 데이터 계층 ---
variable "db_identifier" {
  description = "RDS instance identifier"
  type        = string
  default     = "database-1"
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
  default     = "petclinic-db-subnet-group"
}

# --- 스토리지 · 로그 ---
variable "s3_bucket_name" {
  description = "Static asset bucket"
  type        = string
  default     = "mc-static-image"
}

variable "log_group_names" {
  description = "CloudWatch log group names to inspect"
  type        = list(string)
  default = [
    "/aws/rds/instance/database-1/error",
    "/aws/rds/instance/database-1/slowquery",
    "/aws/rds/instance/database-1/audit",
    "/petclinic/prod/was/petclinic/application",
    "/petclinic/prod/was/tomcat/access",
    "/petclinic/prod/was/tomcat/catalina",
    "/petclinic/prod/web/apache/access",
    "/petclinic/prod/web/apache/error",
    "/petclinic/prod/web/ssh/access",
    "/petclinic/prod/web/bootstrap",
    "/petclinic/prod/bastion/ssh/secure",
  ]
}

# --- 엣지 계층 ---
variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (3-tier entry point)"
  type        = string
  default     = "E1F6M0QDUUT8AG"
}

# CloudFront 오리진 커스텀 헤더 superheader 값 — CloudFront(edge.tf) 가 붙이고, 공개 ALB 443 리스너 규칙(entry.tf)과
# web Apache(userdata/web-v13.sh → compute.tf) 가 검사한다. 공개 리포라 값은 terraform.tfvars 에만 둔다(.gitignore).
variable "cf_origin_secret" {
  description = "CloudFront → 공개 ALB 확인용 헤더(superheader) 값"
  type        = string
  sensitive   = true
}

