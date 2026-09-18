# 조회 결과를 사람이 읽기 좋게 출력한다. `terraform output` 또는 `terraform plan` 으로 확인.

output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.main.id
}

output "subnets" {
  description = "Subnet Name tag -> id, AZ, CIDR"
  value = {
    for name, s in data.aws_subnet.named : name => {
      id                = s.id
      availability_zone = s.availability_zone
      cidr_block        = s.cidr_block
    }
  }
}

output "load_balancers" {
  description = "ALB name -> DNS name, type, scheme"
  value = {
    for name, lb in data.aws_lb.named : name => {
      dns_name = lb.dns_name
      type     = lb.load_balancer_type
      scheme   = lb.internal ? "internal" : "internet-facing"
    }
  }
}

output "target_groups" {
  description = "Target group name -> ARN, port, health check path"
  value = {
    for name, tg in data.aws_lb_target_group.named : name => {
      arn               = tg.arn
      port              = tg.port
      protocol          = tg.protocol
      health_check_path = tg.health_check_path
    }
  }
}

output "asg_web" {
  description = "ASG name, sizes, instance ids, attached target groups"
  value = {
    name             = data.aws_autoscaling_group.web.name
    min_size         = data.aws_autoscaling_group.web.min_size
    max_size         = data.aws_autoscaling_group.web.max_size
    desired_capacity = data.aws_autoscaling_group.web.desired_capacity
    instance_ids     = data.aws_instances.asg.ids
    instance_ips     = data.aws_instances.asg.private_ips
    target_groups    = data.aws_autoscaling_group.web.target_group_arns
    subnets          = data.aws_autoscaling_group.web.vpc_zone_identifier
  }
}

output "launch_template" {
  description = "Launch template name, id and versions"
  value = {
    name            = data.aws_launch_template.web.name
    id              = data.aws_launch_template.web.id
    latest_version  = data.aws_launch_template.web.latest_version
    default_version = data.aws_launch_template.web.default_version
  }
}

output "instances" {
  description = "Standalone instances: Name tag -> id, type, private IP (ASG members: see asg_web)"
  value = {
    for name, i in data.aws_instance.named : name => {
      id            = i.id
      instance_type = i.instance_type
      private_ip    = i.private_ip
      state         = i.instance_state
      iam_profile   = i.iam_instance_profile
    }
  }
}

output "security_groups" {
  description = "Security group name -> id"
  value       = { for name, sg in data.aws_security_group.named : name => sg.id }
}

output "iam" {
  description = "EC2 role ARN and instance profiles"
  value = {
    role_arn          = data.aws_iam_role.ec2.arn
    instance_profiles = { for name, p in data.aws_iam_instance_profile.named : name => p.arn }
  }
}

output "rds_instance" {
  description = "RDS endpoint, engine, class and storage"
  value = {
    identifier     = data.aws_db_instance.main.db_instance_identifier
    endpoint       = data.aws_db_instance.main.endpoint
    engine         = data.aws_db_instance.main.engine
    engine_version = data.aws_db_instance.main.engine_version
    instance_class = data.aws_db_instance.main.db_instance_class
    storage_gb     = data.aws_db_instance.main.allocated_storage
    multi_az       = data.aws_db_instance.main.multi_az
    subnet_group   = data.aws_db_instance.main.db_subnet_group
  }
}

output "rds_proxy" {
  description = "RDS Proxy endpoint and engine family"
  value = {
    name     = data.aws_db_proxy.main.name
    endpoint = data.aws_db_proxy.main.endpoint
    engine   = data.aws_db_proxy.main.engine_family
  }
}

output "db_subnet_group" {
  description = "DB subnet group name and its subnets"
  value = {
    name    = data.aws_db_subnet_group.main.name
    subnets = data.aws_db_subnet_group.main.subnet_ids
  }
}

output "network_extras" {
  description = "Internet gateway, NAT gateways, route tables, VPC endpoint"
  value = {
    internet_gateway = data.aws_internet_gateway.main.id
    nat_gateways     = { for id, ng in data.aws_nat_gateway.named : id => ng.public_ip }
    route_tables     = { for id, rt in data.aws_route_table.named : id => rt.id }
    vpc_endpoint     = data.aws_vpc_endpoint.main.id
  }
}

output "s3_buckets" {
  description = "Inspected S3 bucket"
  value = {
    (var.s3_bucket_name) = data.aws_s3_bucket.static.arn
  }
}

output "log_groups" {
  description = "Log group name -> retention days and KMS key"
  value = {
    for name, lg in data.aws_cloudwatch_log_group.named : name => {
      retention_in_days = lg.retention_in_days
      kms_key_id        = lg.kms_key_id
    }
  }
}