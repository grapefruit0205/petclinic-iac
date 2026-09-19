# 컴퓨트 계층 — 골든 AMI, 시작 템플릿, ASG + 스케일링 정책, 단독 인스턴스 4대, WAS 데이터 볼륨.
# 키페어 `test-key` 는 퍼블릭 키를 API 로 못 읽어 import 할 수 없다 → 이름만 문자열로 쓴다.

# web-ami 인스턴스(i-0c205c2e12ea8e389)에서 CreateImage 로 만든 골든 이미지. ASG 시작 템플릿 전 버전이 쓴다.
resource "aws_ami" "web_apache" {
  name                = "web-appache"
  description         = "install apache web"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-0afb030a6929fe286"
    volume_size           = 8
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }
}

# ASG 시작 템플릿. 실물은 latest=5(t3.small), default=4(t2.small). ASG 는 5 를 고정해 쓴다.
# 이 블록은 latest(5) 의 내용이다 — 속성을 바꾸면 v6 이 생기고 default_version 은 그대로 4 다.
resource "aws_launch_template" "web" {
  name            = "web"
  default_version = 4

  image_id      = aws_ami.web_apache.id
  instance_type = "t3.small"
  key_name      = "test-key"
  user_data     = base64encode(file("${path.module}/userdata/web.sh"))

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.web.id]
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "web-test"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private1_2a.id, aws_subnet.private2_2c.id]
  target_group_arns   = [aws_lb_target_group.web.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 60
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "5" # $Latest 가 아니라 버전 고정
  }

  # 그룹 지표 전부 켜져 있음
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupAndWarmPoolDesiredCapacity", "GroupAndWarmPoolTotalCapacity", "GroupDesiredCapacity",
    "GroupInServiceCapacity", "GroupInServiceInstances", "GroupMaxSize", "GroupMinSize",
    "GroupPendingCapacity", "GroupPendingInstances", "GroupStandbyCapacity", "GroupStandbyInstances",
    "GroupTerminatingCapacity", "GroupTerminatingInstances", "GroupTerminatingRetainedCapacity",
    "GroupTerminatingRetainedInstances", "GroupTotalCapacity", "GroupTotalInstances",
    "WarmPoolDesiredCapacity", "WarmPoolMinSize", "WarmPoolPendingCapacity",
    "WarmPoolPendingRetainedCapacity", "WarmPoolTerminatingCapacity",
    "WarmPoolTerminatingRetainedCapacity", "WarmPoolTotalCapacity", "WarmPoolWarmedCapacity",
  ]

  tag {
    key                 = "Name"
    value               = "ASG-Web"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "test"
    propagate_at_launch = true
  }

  # 아래 4개는 AWS API 가 아닌 Terraform 전용 인자라 import 로 state 에 들어오지 않는다.
  # 무시하지 않으면 apply 전까지 plan 에 "변경" 으로 계속 잡힌다.
  lifecycle {
    ignore_changes = [force_delete, force_delete_warm_pool, ignore_failed_scaling_activities, wait_for_capacity_timeout]
  }
}

# CPU 60% 목표 추적. 알람 2개(TargetTracking-web-test-AlarmHigh/Low)는 이 정책이 만들고 소유한다.
resource "aws_autoscaling_policy" "web_cpu" {
  name                      = "Target Tracking Policy"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 60

  target_tracking_configuration {
    target_value     = 60
    disable_scale_in = false

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}

# --- 단독 인스턴스 4대 ---
# WAS. Tomcat 8080, tg-internal-alb 의 유일한 타깃 (SPOF). 프로파일 was-test-iam (AmazonRDSFullAccess).
resource "aws_instance" "was_test_a" {
  ami                         = "ami-0fad23d064f9e8330"
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.private3_2a.id
  private_ip                  = "10.0.20.235"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.was.id]
  key_name                    = "test-key"
  iam_instance_profile        = aws_iam_instance_profile.was.name
  monitoring                  = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
  }
  # 추가 데이터 볼륨(/dev/sdf, 암호화)은 aws_ebs_volume.was_data + aws_volume_attachment.was_data 로 관리

  tags = {
    Name = "WAS-test-a"
  }
}

# ASG 밖에서 Targetgroup-web 에 수동 등록된 web 1대. 프로파일 없음 → SSM 미관리.
resource "aws_instance" "web_test_a" {
  ami                         = "ami-0fad23d064f9e8330"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private1_2a.id
  private_ip                  = "10.0.10.51"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = "test-key"
  monitoring                  = false

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name = "WEB-test-a"
  }
}

# 베스천. 퍼블릭 서브넷, 퍼블릭 IP 자동 할당(EIP 아님). 프로파일 없음.
resource "aws_instance" "bastion" {
  ami                         = "ami-0fad23d064f9e8330"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public1_2a.id
  private_ip                  = "10.0.0.196"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = "test-key"
  monitoring                  = false

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name = "bas-server"
  }
}

# 골든 이미지 원본. 퍼블릭 서브넷에 퍼블릭 IP 로 계속 켜져 있다 (t2.medium, 상세 모니터링 on).
resource "aws_instance" "web_ami" {
  ami                         = "ami-010bbf6096e7bb791"
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.public1_2a.id
  private_ip                  = "10.0.0.133"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = "test-key"
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  monitoring                  = true
  user_data                   = file("${path.module}/userdata/web-ami.sh") # 시작 시 1회 실행된 스크립트 (state 엔 sha1 만 남는다)

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name = "web-ami"
  }
}

# WAS 데이터 볼륨 — 계정에서 유일하게 암호화된 EBS (KMS 고객 키).
resource "aws_ebs_volume" "was_data" {
  availability_zone = "ap-northeast-2a"
  size              = 20
  type              = "gp3"
  encrypted         = true
  kms_key_id        = "arn:aws:kms:ap-northeast-2:723165663216:key/fffaccce-417f-4d19-a593-dfd6214a8eb8"
}

resource "aws_volume_attachment" "was_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.was_data.id
  instance_id = aws_instance.was_test_a.id
}
