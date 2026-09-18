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

variable "vpc_endpoint_id" {
  description = "VPC endpoint ID"
  type        = string
  default     = "vpce-0bc81ff97ecbceb74"
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
  description = "Name tags of standalone instances (ASG members are covered by the ASG lookup)"
  type        = list(string)
  default     = ["WAS-test-a", "WEB-test-a", "bas-server", "web-ami"]
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

variable "db_proxy_name" {
  description = "RDS Proxy name"
  type        = string
  default     = "pet-proxy"
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
    "/aws/rds/proxy/pet-proxy",
  ]
}