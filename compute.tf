# 컴퓨트 계층 — 골든 AMI 3개(web·was v1·was v2), 시작 템플릿 2개, ASG 2개 + 스케일링 정책, 단독 인스턴스 5대, WAS 데이터 볼륨.
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

# ASG 시작 템플릿. 목표 상태는 latest=12 = default=12, ASG 는 12 고정. 이 블록은 latest(12) 의 내용.
# (2026-09-24 코드 먼저 v12 로 올림 — terraform apply -target(LT·ASG) + 인스턴스 리프레시 전까지 plan 에 LT·ASG 변경으로 나온다)
# v6 (2026-09-19): user data 에 CloudFront 커스텀 헤더(superheader) 검사 — ALB 직접 접근은 403. (userdata/web.sh 로 보관)
# v7 (2026-09-22): v6 + access 로그 첫 칸 X-Forwarded-For(사용자 IP)·%D 처리시간, logrotate 3일, rsyslog(/var/log/secure),
#   로그 그룹 이름 규칙 /petclinic/prod/web/…, 디스크·메모리 지표(PetClinic/WEB), 루트 30GB gp3, 인스턴스·볼륨 태그.
# v8 (2026-09-22 17:33, kdt5 — 의도한 변경): v7 과 user data 동일, 프로파일만 mc-ec2-role → CloudWatchAgentServerPolicy(CloudWatch 만).
#   ⚠️ 이 역할엔 SSM 이 없어 v8 부터 web 은 Session Manager·Run Command 불가(SSH 는 베스천 경유).
# v9 (2026-09-23 14:13): 에이전트 설정을 Parameter Store(AmazonCloudWatch-petclinic-web)에서 읽게 — 같은 날 되돌림(파라미터 삭제).
# v10 (2026-09-23 14:33, 14:40 리프레시 5e20dfdb): 설정 JSON 다시 인라인(v7 방식) + 그룹별 retention_in_days. v9 와는 user data 만 다름.
#   web 은 Session Manager 가 없어 파라미터를 고쳐도 리프레시가 필요 → Parameter Store 이점 없이 부팅 의존만 늘어서 되돌림.
#   보존기간을 에이전트가 직접 걸므로 로그 그룹을 미리 만들 필요가 없다 (v9 에서 apache/access 무기한→30일, ssh/access 자동 생성 실측).
# v11 (2026-09-24): v10 + ProxyPass ttl=55. 부하 테스트 S5 재실행 02:13:00 KST 에 POST 1건 502 — Apache 가 내부 ALB 가 이미 닫은
#   keep-alive 연결을 재사용(AH01102 error reading status line). 내부 ALB idle timeout 60초보다 짧게 Apache 가 먼저 연결을 정리한다.
#   12:32 CLI 로 v11 생성·기본 11·ASG 11 → 리프레시 a3ddf313 (12:32~12:36 성공). 12:38 S5 3차에서 AH01102 0건.
# v12 (2026-09-24): v11 + KeepAliveTimeout 65. S5 3차 502 9건은 공개 ALB 가 만든 ELB 502(대상 web, target_status '-', Apache 로그 0) —
#   Apache(event MPM) 기본 KeepAliveTimeout 5초 < 공개 ALB idle timeout 60초라 Apache 가 막 닫은 연결에 ALB 가 요청을 보냈다.
resource "aws_launch_template" "web" {
  name            = "web"
  description     = "v12: KeepAliveTimeout 65 (public ALB idle 60s, ELB 502)" # 최신 버전의 버전 설명 — 콘솔 입력과 글자까지 같아야 plan 이 조용하다
  default_version = 12

  image_id      = aws_ami.web_apache.id
  instance_type = "t3.small"
  key_name      = "test-key"
  user_data     = base64encode(file("${path.module}/userdata/web-v12.sh"))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ASG-Web"
      Tier = "web"
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "web-root"
      Tier = "web"
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.cw_agent.arn # v8 은 이름이 아니라 ARN 으로 지정돼 있다
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
  health_check_grace_period = 120 # v7: 부팅 시 dnf 설치(에이전트·rsyslog)가 60초를 넘길 수 있어 2026-09-22 60→120
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "12" # $Latest 가 아니라 버전 고정. 바꾸면 인스턴스 리프레시로 교체해야 반영된다 (9/22 6→7 리프레시 482197d8, 9/23 8→9 49278dd3, 9→10 5e20dfdb, 9/24 10→11 a3ddf313, 11→12)
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

# 2026-09-21 콘솔 추가: Public ALB 타깃당 요청수 기반 단계 스케일 아웃. 트리거 알람은 monitoring.tf 의 web_reqcount_high.
# 단계 = 알람 임계치(20000) 기준 초과분 0~15000 → +1대, 15000 이상 → +2대. 이름의 "cale-out" 은 콘솔에서 입력한 오타 그대로.
# 스케일 인 정책은 없다 — 줄이는 건 CPU 목표 추적(web_cpu)이 맡는다.
resource "aws_autoscaling_policy" "web_reqcount" {
  name                      = "cale-out-web-reqcount-20000~35000"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 300  # 2026-09-22 명시 (없으면 ASG 쿨다운 값에 묶임)
  enabled                   = true # 2026-09-24 01:23 S5 준비 중 콘솔에서 끔 → 9/24 다시 켬. 끄면 요청 수로는 web 이 늘지 않는다

  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 15000
    scaling_adjustment          = 1
  }
  step_adjustment {
    metric_interval_lower_bound = 15000
    scaling_adjustment          = 2
  }
}

# --- WAS 계층 ASG (2026-09-21 콘솔 생성, WAS 담당) ---
# 골든 이미지: was-goldenImage 인스턴스(아래)에서 CreateImage. 루트 20GB 비암호화 — 암호화는 시작 템플릿에서 KMS 로 덧씌운다.
resource "aws_ami" "was_golden" {
  name                = "was-goldenImage-test"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-07051adf4b3544465"
    volume_size           = 20
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }
}

# 골든 이미지 v2 (2026-09-21 18:38 KST, semin): was-gg2 인스턴스(아래)에서 CreateImage. v1 과 같은 구성(루트 20GB 비암호화). 시작 템플릿 v2 가 쓴다.
# 골든 이미지 v4 (2026-09-22 19:11 KST, semin): was-gg2 에서 CreateImage. CloudWatch Agent 설치 포함. 시작 템플릿 v3·v4 가 쓴다.
# (같은 날 19:03 의 v3 이미지 ami-0e67b368a44b87813 은 이미 등록 취소돼 없다.)
resource "aws_ami" "was_golden_v4" {
  name                = "was-goldenImage-v4"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-00b515e624b9e2f57"
    volume_size           = 20
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }
}

resource "aws_ami" "was_golden_v2" {
  name                = "was-goldenImage-test-v2"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-07a6743c7b1f78155"
    volume_size           = 20
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }
}

# 시작 템플릿 was-lt. 실물은 latest=4 = default=4, ASG 는 $Latest. 이 블록은 latest(v4) 의 내용.
# v1 (17:20 KST): AMI was-goldenImage-test, 루트도 KMS 암호화, 설명 "was 웹서버 시작 템플릿".
# v2 (18:42 KST, semin): AMI was-goldenImage-test-v2 로 교체, 루트 비암호화, /dev/sdf 처리량 미지정, 설명 없음. user data 는 v1 과 동일.
# v3·v4 (2026-09-22 19:15·19:25 KST, semin): AMI was-goldenImage-v4(에이전트 설치됨) + user data 끝에 CloudWatch Agent 기동
#   (`fetch-config -c ssm:/petclinic/cwagent/was` — jaewoon 의 Parameter Store 설정). 루트 매핑은 빼고 AMI 기본값, /dev/sdf 만 지정.
#   19:32~19:44 WAS 2대를 수동 종료 → ASG 가 v4 로 재생성.
# t3.medium, 프로파일 was-test-iam (RDS·SSM Core·시크릿 읽기 — ⚠️ CloudWatchAgentServerPolicy 없음 → 로그 전송 불가).
resource "aws_launch_template" "was" {
  name            = "was-lt"
  default_version = 4

  image_id      = aws_ami.was_golden_v4.id
  instance_type = "t3.medium"
  key_name      = "test-key"
  user_data     = base64encode(file("${path.module}/userdata/was-lt.sh"))

  iam_instance_profile {
    arn = aws_iam_instance_profile.was.arn
  }

  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.was.id]
  }

  block_device_mappings {
    device_name = "/dev/sdf"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      iops                  = 3000
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = "arn:aws:kms:ap-northeast-2:723165663216:key/fffaccce-417f-4d19-a593-dfd6214a8eb8"
    }
  }

  # 콘솔은 KMS 키를 ARN 이 아니라 키 ID("fffaccce-…")로 저장했다. provider 는 ARN 만 받으므로 코드엔 ARN 을 쓰고,
  # 그 표기 차이가 plan 에 "변경" 으로 잡히지 않게 무시한다 (같은 키).
  lifecycle {
    ignore_changes = [block_device_mappings[0].ebs[0].kms_key_id]
  }
}

# WAS ASG. WAS 서브넷(private3/4) 2~4대, tg-internal-alb 에 등록. 시작 템플릿은 $Latest 를 따라간다(2026-09-21 18:43 KST
# $Default → $Latest, semin; web-test 는 버전 고정). 18:46~18:52 KST 2대가 v2 로 교체됨. 그룹 지표(enabled_metrics)는 안 켜져 있다. 유예 300초.
resource "aws_autoscaling_group" "was" {
  name                = "was-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private4_2c.id, aws_subnet.private3_2a.id]
  target_group_arns   = [aws_lb_target_group.was.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.was.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ASG-Was"
    propagate_at_launch = true
  }

  # web 과 같은 이유 — Terraform 전용 인자 4개.
  lifecycle {
    ignore_changes = [force_delete, force_delete_warm_pool, ignore_failed_scaling_activities, wait_for_capacity_timeout]
  }
}

# CPU 60% 목표 추적 (web 과 동일). 알람 TargetTracking-was-asg-AlarmHigh/Low 는 이 정책이 소유.
resource "aws_autoscaling_policy" "was_cpu" {
  name                      = "Target Tracking Policy"
  autoscaling_group_name    = aws_autoscaling_group.was.name
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

# --- 단독 인스턴스 5대 ---
# 옛 WAS(수제). Tomcat 8080. 2026-09-21 WAS ASG(was-asg) 로 대체되며 tg-internal-alb 에서 등록 해제, 2026-09-22 13:27 KST semin 이 **중지**
# (실험용 보관, 프라이빗 서브넷이라 퍼블릭 IP 해제 문제 없음). 종료하면 이 블록 + was_data 볼륨·연결 블록 삭제 + state rm.
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

# ASG 밖의 수제 web 1대. 2026-09-19 21:45 KST Targetgroup-web 에서 등록 해제(헤더 검사 없는 v5 설정이라 우회 경로였음)
# → 트래픽 안 받음. WEB 계층 실험용으로 남기고 mc-ec2-role 을 붙여 SSM 접속 가능하게 함. 22:21 KST 중지(비용) — 필요할 때 시작.
resource "aws_instance" "web_test_a" {
  ami                         = "ami-0fad23d064f9e8330"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private1_2a.id
  private_ip                  = "10.0.10.51"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = "test-key"
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
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

# 베스천. 퍼블릭 서브넷, 퍼블릭 IP 자동 할당(EIP 아님). 2026-09-22 프로파일 bastion-role 부착(CloudWatch 만) + 에이전트가
# /var/log/secure 를 /petclinic/prod/bastion/ssh/secure 로 전송 (인스턴스 안 수동 설치 — 재생성 시 user data 로 옮길 것).
# 운영 방침(2026-09-21 결정): 베스천 유지. EICE 는 정리됨. 다음 손볼 것: SG-bastion 22 를 팀원 IP 로 축소, EIP.
resource "aws_instance" "bastion" {
  ami                         = "ami-0fad23d064f9e8330"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public1_2a.id
  private_ip                  = "10.0.0.196"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = "test-key"
  iam_instance_profile        = aws_iam_instance_profile.cw_agent.name # 2026-09-22 17:36 bastion-role → CloudWatchAgentServerPolicy
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

  # web_ami 와 같은 이유 — 중지 시 퍼블릭 IP 해제로 replace 가 뜨는 것을 막는다.
  lifecycle {
    ignore_changes = [associate_public_ip_address]
  }
}

# 골든 이미지 web-appache 의 원본 (9/15 CreateImage). 역할이 끝나 2026-09-19 22:35 KST 중지 — AMI 는 원본과 독립이라 영향 없음.
# 다시 구울 일(OS·httpd 패키지 갱신)이 생기면 시작해서 쓰거나, 현재 AMI 로 새 인스턴스를 띄워 만든다. (t2.medium, 상세 모니터링 on)
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

  # 자동 할당 퍼블릭 IP 는 중지하면 해제돼 provider 가 associate_public_ip_address 를 false 로 읽고,
  # 이 인자는 ForceNew 라 plan 이 "must be replaced"(삭제 후 재생성) 를 내놓는다. 절대 그렇게 되면 안 되므로 무시한다.
  lifecycle {
    ignore_changes = [associate_public_ip_address]
  }
}

# (골든 이미지 v1 원본 was-goldenImage 인스턴스는 2026-09-22 13:27 KST semin 이 종료 — AMI 는 원본과 독립이라 영향 없음. 블록·state 제거.)

# 골든 이미지 v2 의 원본 was-gg2 (2026-09-21 18:04 KST v1 AMI 로 생성 → 손본 뒤 18:38 CreateImage, semin). 20:58 다시 시작해 running —
# 타깃 그룹엔 없으니 트래픽은 안 받는다(다음 골든 이미지 작업용으로 추정).
# was-goldenImage 와 마찬가지로 DB 서브넷(private5, 10.0.30.x) 에 있다. 데이터 볼륨(/dev/sdf) 없이 루트만.
resource "aws_instance" "was_gg2" {
  ami                         = aws_ami.was_golden.id # was-goldenImage-test (v1)
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.private5_2a.id
  private_ip                  = "10.0.30.167"
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

  tags = {
    Name = "was-gg2"
  }
}

# WAS 데이터 볼륨 — WAS-test-a 의 /dev/sdf (KMS 고객 키 암호화). ASG 인스턴스는 시작 템플릿의 두 번째 BDM 이 같은 키로 따로 만든다.
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
