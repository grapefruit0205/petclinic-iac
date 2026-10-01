# 컴퓨트 계층 — 골든 AMI 6개(web · was test·v2·v4·v5·v6), 시작 템플릿 2개, ASG 2개 + 스케일링 정책, 단독 인스턴스 4대, WAS 데이터 볼륨.
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

# ASG 시작 템플릿. 실물은 latest=14 · default=13, ASG 는 13 고정. 이 블록은 latest(14) 의 내용 — provider 는 최신 버전을 읽는다.
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
#   14:44 apply -target → 리프레시 154ff1bb (14:44~14:47 성공). 새 서버에서 10초 쉰 연결 재사용 확인.
#   (정정 9/24 16시: 3차 9건은 12:39:00·01·12:40:02 — 매분 00~02초라 원인은 v13 쪽. v12 뒤 15:06:00~02·15:07:00 에도 8건.
#    KeepAliveTimeout 65 는 AWS 권장값이라 그대로 둔다.)
# v13 (2026-09-24): v12 + Apache 작업 스레드 1024개(16 × 64)를 부팅 때 미리 띄움. S5 단계 상승(15:05~15:18) ELB 502 2,023건 —
#   매분 00초 DB 쪽 지연(부하 중 최대 1.7초) 동안 쌓인 요청으로 Apache 프로세스 하나의 스레드(기본 25개)가 다 차면 event MPM 이
#   그 프로세스의 쉬는 keep-alive 연결을 닫아 ALB 가 보낸 요청이 끊겼다. 00초 지연 자체는 DB 쪽이라 이걸로 없어지지 않는다(502 → 잠깐 느림).
#   17:34 apply -target → 리프레시 fa39dcce (17:34~17:38 성공). 18:38 S5 재실행에서 502 2,023 → 1건.
#   버전 설명 "v13: 1024 event MPM workers started at boot (16x64) - ELB 502 at minute :00".
# v14 (2026-09-24 19:59 KST, yena 콘솔): v13 과 user data·나머지 동일, 인스턴스 프로파일만 CloudWatchAgentServerPolicy → web-iam
#   (새 역할, 권한은 같은 CloudWatch Agent 정책 하나 — iam.tf). 버전 설명 없음. 기본 버전·ASG 는 아직 13 이라 떠 있는 web 은 v13.
# v15 (2026-09-28 초안, 발표 뒤 적용): v14 + Apache 스레드 사용률 지표(상태 페이지 127.0.0.1:81 + web-thread-metric 서비스) — userdata/web-v15.sh.
#   아래 web_threads_out · web_threads_in 정책(monitoring.tf 의 스레드 알람)이 ApacheBusyThreadsMax 로 늘리고 줄인다. apply 뒤 인스턴스 리프레시로 교체해야 반영된다.
#   2026-09-28 19:0x apply · 리프레시 4459e0ca 완료(19:02–19:07).
resource "aws_launch_template" "web" {
  name            = "web"
  default_version = 15

  image_id      = aws_ami.web_apache.id
  instance_type = "t3.small"
  key_name      = "test-key"
  # 스크립트의 __CF_SECRET__ 자리에 terraform.tfvars 의 값을 넣는다 → 실물 user data 와 글자까지 같다.
  user_data = base64encode(replace(file("${path.module}/userdata/web-v15.sh"), "__CF_SECRET__", var.cf_origin_secret))

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
    arn = aws_iam_instance_profile.web.arn # v14. v8~v13 은 cw_agent 프로파일 (이름이 아니라 ARN 으로 지정)
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
  max_size            = 4 # 2026-09-28 kdt5: 6 으로 올리는 초안(스레드 기준 확장과 같이)은 보류 — 일단 4 유지
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private1_2a.id, aws_subnet.private2_2c.id]
  target_group_arns   = [aws_lb_target_group.web.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 120 # v7: 부팅 시 dnf 설치(에이전트·rsyslog)가 60초를 넘길 수 있어 2026-09-22 60→120
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "15" # $Latest 가 아니라 버전 고정. 바꾸면 인스턴스 리프레시로 교체해야 반영된다 (9/22 6→7 리프레시 482197d8, 9/23 8→9 49278dd3, 9→10 5e20dfdb, 9/24 10→11 a3ddf313, 11→12 154ff1bb, 12→13 fa39dcce, 13→15 = 발표 뒤)
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

# (2026-09-30) CPU 60% 목표 추적 정책("Target Tracking Policy", 늘리기만) 삭제 — web CPU 는 몰려도 7~15% 라 울린 적이 없고,
#   web 을 늘리고 줄이는 기준은 아래 스레드 최대 개수 하나로 둔다. 정책을 지우면 AWS 가 알람 TargetTracking-web-test-AlarmHigh 도 지운다.

# web 을 늘리고 줄이는 기준 = Apache 작업 스레드 "최대" 개수(시작 템플릿 v15 가 보내는 PetClinic/WEB ApacheBusyThreadsMax,
# web 1대가 1분 동안 10초마다 잰 BusyWorkers 중 가장 큰 값 · 차원 AutoScalingGroupName 하나 → 통계 Maximum = 가장 바쁜 web 1대).
# 요청 수 단계 정책(옛 web_reqcount, "cale-out-web-reqcount-20000~35000")을 대신한다. 근거는 userdata/web-v15.sh 머리 주석 —
#   요청이 많아도 뒤가 빠르면 스레드를 거의 안 쓰고, 뒤(DB 복제본)가 느려질 때만 오른다.
# 2026-09-28 19:0x 처음엔 평균 %(ApacheBusyThreadsPct) 목표 추적 50% 로 apply → 같은 날 19:09 S5 에서 web 이 한 번도 안 늘었다:
#   스레드는 몇 초씩 몰렸다 빠져서(가장 바쁜 1대 19:15 437 · 19:18 865 · 19:20 1,007개 / 1,024) 1분 평균은 7 · 20 · 48% 로 뭉개졌고,
#   목표 추적은 "3분 연속 초과"(바꿀 수 없음)라 19:21 평균 96.7% 로 다 찼을 때도 부하가 먼저 끝났다 — 에러 1만 2천여 건(0.69%).
# → 알람 + 단계 정책으로 바꿈. 늘리기: 가장 바쁜 web 이 1분이라도 512개(50%) 이상. 줄이기: 15분 내내 128개(12.5%) 미만.
#   부하 중엔 튀는 값이 계속 128 을 넘으므로 줄이기가 끼어들지 않는다(9/27 S5 의 늘리기 · 줄이기 줄다리기 502 151건 방지).
#   Auto Scaling 동작이 붙은 알람은 ALARM 인 동안 1분마다 정책을 다시 부른다 — 새 web 은 준비(warmup) 180초 동안 대수에 이미 셈해져 과하게 늘지 않는다.
resource "aws_autoscaling_policy" "web_threads_out" {
  name                      = "web-apache-threads-max-out"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Maximum"
  estimated_instance_warmup = 180 # 부팅 때 dnf 설치(에이전트·rsyslog) 뒤 지표가 나오기까지 — health_check_grace_period 120 보다 넉넉히

  # 경계는 알람 기준 512 를 0 으로 본 차이: 512–819개 → +1, 820개(80%) 이상 → +2
  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 308
    scaling_adjustment          = 1
  }
  step_adjustment {
    metric_interval_lower_bound = 308
    scaling_adjustment          = 2
  }
}

resource "aws_autoscaling_policy" "web_threads_in" {
  name                    = "web-apache-threads-max-in"
  autoscaling_group_name  = aws_autoscaling_group.web.name
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Maximum"

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
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

# 골든 이미지 v5 (2026-09-24 15:21 KST, semin): was-gg2 에서 CreateImage(재부팅). WAR 에 커넥션 풀 maxActive 20 · maxIdle 10 ·
# validationQuery `SELECT 1` 반영 (부하 테스트 S5 1차의 "Too many connections" 대책을 이미지에 굳힘). 시작 템플릿 v6 이 쓴다.
resource "aws_ami" "was_golden_v5" {
  name                = "was-goldenImage-v5"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-0194f87a30c60cc6c"
    volume_size           = 20
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }
}

# 골든 이미지 v6 (2026-09-27 03:44 KST, semin): was-gg2 에서 CreateImage(재부팅). 9/26 밤 DB 이름·비밀번호 방식이 바뀐 뒤
# WAS 가 뜨지 못하던 것을 was-gg2 에서 고쳐 굳힌 이미지(고친 내용은 semin 확인 필요). 시작 템플릿 v7 이 쓴다.
resource "aws_ami" "was_golden_v6" {
  name                = "was-goldenImage-v6"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"
  boot_mode           = "uefi-preferred"
  imds_support        = "v2.0"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = "snap-074fad84289cfaccb"
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

# 시작 템플릿 was-lt. 실물은 latest=8 · default=5, ASG 는 버전 7 고정. 이 블록은 latest(v8) 의 내용 — provider 는 최신 버전을 읽는다.
# v1 (17:20 KST): AMI was-goldenImage-test, 루트도 KMS 암호화, 설명 "was 웹서버 시작 템플릿".
# v2 (18:42 KST, semin): AMI was-goldenImage-test-v2 로 교체, 루트 비암호화, /dev/sdf 처리량 미지정, 설명 없음. user data 는 v1 과 동일.
# v3·v4 (2026-09-22 19:15·19:25 KST, semin): AMI was-goldenImage-v4(에이전트 설치됨) + user data 끝에 CloudWatch Agent 기동
#   (`fetch-config -c ssm:/petclinic/cwagent/was` — jaewoon 의 Parameter Store 설정). 루트 매핑은 빼고 AMI 기본값, /dev/sdf 만 지정.
#   19:32~19:44 WAS 2대를 수동 종료 → ASG 가 v4 로 재생성.
# v5 (2026-09-24 14:56 KST, semin): v4 + 세부 모니터링(1분 CPU) 켬 — 부하 테스트 S5 에서 5분 지표로는 2분 단계를 못 나눠서. 기본 버전 5.
# v6 (2026-09-24 15:25 KST, semin): v5 + AMI was-goldenImage-v5(풀 20). 기본 버전은 5 그대로 두고 ASG 가 $Latest 라 새 WAS 는 v6.
#   15:27~15:31 WAS 2대 교체 → 10.0.21.37 · 10.0.20.190. user data 는 v4~v6 모두 같다.
# v7 (2026-09-27 03:49 KST, semin): v6 + AMI was-goldenImage-v6. user data 는 그대로. 기본 버전은 5 그대로.
#   01:46 ASG 를 0대로 내렸다가 03:49 2대로 되돌림 → i-04be34630a6d5a368 · i-0648caed79a4a49e7 (v7).
# v8 (2026-09-28 17:43 KST, yena): AMI 를 was-goldenImage-v4 로 되돌리고 루트(/dev/xvda) 매핑을 KMS 암호화로 명시(스냅샷 = v4 AMI 의 것).
#   user data 는 v7 과 같다. 이 버전으로 뜬 새 WAS 가 연속으로 상태 확인에 실패 → kdt5 가 ASG 를 버전 7 로 고정(아래 ASG).
#   그래서 v8 은 실제로 쓰이지 않는다. 이 블록을 apply 하면 v9 가 새로 생길 뿐 ASG 는 7 그대로.
# t3.medium, 프로파일 was-test-iam (시크릿 읽기 · SSM Core · CloudWatch Agent — iam.tf).
resource "aws_launch_template" "was" {
  name            = "was-lt"
  default_version = 5

  image_id      = aws_ami.was_golden_v4.id # v8. ASG 가 쓰는 v7 은 was_golden_v6
  instance_type = "t3.medium"
  key_name      = "test-key"
  user_data     = base64encode(file("${path.module}/userdata/was-lt.sh"))

  # v5 부터 세부 모니터링(1분 지표).
  monitoring {
    enabled = true
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.was.arn
  }

  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.was.id]
  }

  # v8: 루트도 KMS 암호화로 명시
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      snapshot_id           = "snap-00b515e624b9e2f57" # was-goldenImage-v4 의 루트 스냅샷
      volume_size           = 20
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = "arn:aws:kms:ap-northeast-2:723165663216:key/fffaccce-417f-4d19-a593-dfd6214a8eb8"
    }
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
    ignore_changes = [
      block_device_mappings[0].ebs[0].kms_key_id,
      block_device_mappings[1].ebs[0].kms_key_id,
    ]
  }
}

# WAS ASG. WAS 서브넷(private3/4) 2~6대(2026-09-28 21시 kdt5 결정, 전에는 2~4), tg-internal-alb 에 등록. 유예 300초.
# 시작 템플릿: 2026-09-21 18:43 KST $Default → $Latest(semin) 였다가, 9/28 v8(yena, AMI was-goldenImage-v4)로 새 WAS 가
# 연속 실패 → kdt5 가 콘솔에서 버전 7 로 고정. 코드도 7 로 맞춤($Latest 로 두면 apply 때 v8 로 되돌아간다).
# 그룹 지표: 2026-09-28 전에는 꺼져 있어 대시보드 ⑦·⑫ 의 WAS 대수 선이 비어 있었다 → web 과 같이 전부 켬(무료, 1분). 켠 뒤부터만 쌓인다.
resource "aws_autoscaling_group" "was" {
  name                = "was-asg"
  min_size            = 2
  max_size            = 6 # 2026-09-28 21시 kdt5: 4 → 6 (web 은 4 그대로)
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private4_2c.id, aws_subnet.private3_2a.id]
  target_group_arns   = [aws_lb_target_group.was.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.was.id
    version = "7" # 콘솔 고정값(위 주석)
  }

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
    value               = "ASG-Was"
    propagate_at_launch = true
  }

  # web 과 같은 이유 — Terraform 전용 인자 4개.
  lifecycle {
    ignore_changes = [force_delete, force_delete_warm_pool, ignore_failed_scaling_activities, wait_for_capacity_timeout]
  }
}

# CPU 목표 추적. 9/26 s5-3300 실측(5분 최대 54.7%) 후 60 → 50. 알람 TargetTracking-was-asg-AlarmHigh/Low 는 이 정책이 소유.
# 주의(9/26 결론): WAS 는 DB 응답 대기가 대부분이라 CPU 가 낮게 머문다 — 기준을 내려도 병목(DB CPU) 해소와는 무관하고,
# 부하 중 증설 장면은 "늘려도 처리량 그대로(병목 DB 입증)" 자료로 기록할 것.
# AlarmLow(CPU 35% 미만 15분)는 알림이 아니라 "줄이기" 신호 — Slack 으로 가지 않고, 한가할 때 늘 경보 상태인 게 정상이다
# (9/28 11:56 WAS 2→3 을 12:11 에 3→2 로 되돌린 것이 이 알람). 없애려면 disable_scale_in = true — 그러면 WAS 도 web 처럼 손으로 줄여야 한다.
resource "aws_autoscaling_policy" "was_cpu" {
  name                      = "Target Tracking Policy"
  autoscaling_group_name    = aws_autoscaling_group.was.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 60

  target_tracking_configuration {
    target_value     = 50
    disable_scale_in = false

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}

# --- 단독 인스턴스 4대 (WAS-test-a 는 2026-09-28 종료) ---
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

# WAS 데이터 볼륨 — 옛 WAS-test-a 의 /dev/sdf (KMS 고객 키 암호화). ASG 인스턴스는 시작 템플릿의 /dev/sdf 매핑이 같은 키로 따로 만든다.
# 2026-09-28 15:27 KST semin 이 WAS-test-a(i-0d7f99e2758122059)를 종료 → 인스턴스 · 연결(aws_volume_attachment) 블록은 뺐다.
#   이 볼륨은 종료 때 지워지지 않고 남아 있다(available, 연결 없음) — 지울지는 WAS 담당 결정.
resource "aws_ebs_volume" "was_data" {
  availability_zone = "ap-northeast-2a"
  size              = 20
  type              = "gp3"
  encrypted         = true
  kms_key_id        = "arn:aws:kms:ap-northeast-2:723165663216:key/fffaccce-417f-4d19-a593-dfd6214a8eb8"
}
