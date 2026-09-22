# 콘솔로 만든 실물을 resource 블록에 연결하는 import 선언.
# apply 전까지는 state 에 아무것도 기록되지 않는다 — plan 이 "N to import, 0 to change" 이면 코드가 실물과 일치한다는 뜻.
# 코드 생성:  terraform plan -generate-config-out=generated.tf   (대상 resource 블록이 아직 없을 때만)

# --- 네트워크 ---
import {
  to = aws_vpc.main
  id = "vpc-0f9bca319ec78e918"
}

import {
  to = aws_subnet.public1_2a
  id = "subnet-09eb0c07a081d6199"
}
import {
  to = aws_subnet.public2_2c
  id = "subnet-0776ae1b0074673f3"
}
import {
  to = aws_subnet.private1_2a
  id = "subnet-025eae99d89728a00"
}
import {
  to = aws_subnet.private2_2c
  id = "subnet-07e817528f40582e4"
}
import {
  to = aws_subnet.private3_2a
  id = "subnet-037f65b1f10cad853"
}
import {
  to = aws_subnet.private4_2c
  id = "subnet-0298ce95f08db7c34"
}
import {
  to = aws_subnet.private5_2a
  id = "subnet-0476d35e804dddf1f"
}
import {
  to = aws_subnet.private6_2c
  id = "subnet-0c28846b9d000850c"
}

import {
  to = aws_internet_gateway.main
  id = "igw-05f4e29cd2ff09752"
}

import {
  to = aws_eip.nat_2a
  id = "eipalloc-09598fb9ebd0460a4"
}
import {
  to = aws_eip.nat_2c
  id = "eipalloc-0196daa01b5a67fa6"
}

import {
  to = aws_nat_gateway.public1_2a
  id = "nat-054321cb4593659a4"
}
import {
  to = aws_nat_gateway.public2_2c
  id = "nat-04c67db946fbf7f5a"
}

import {
  to = aws_route_table.public
  id = "rtb-0bf2b5476a7fee7c9"
}
import {
  to = aws_route_table.private1_2a
  id = "rtb-058eadff3c8ed4570"
}
import {
  to = aws_route_table.private2_2c
  id = "rtb-0c5562e8a11dc4143"
}
import {
  to = aws_route_table.private3_2a
  id = "rtb-002a230031020932d"
}
import {
  to = aws_route_table.private4_2c
  id = "rtb-0e37a33af01492fee"
}
import {
  to = aws_default_route_table.main
  id = "vpc-0f9bca319ec78e918" # aws_default_route_table 은 VPC ID 로 import 한다 (main 테이블 rtb-03ed73d98ca97ee51)
}

import {
  to = aws_route_table_association.public1_2a
  id = "subnet-09eb0c07a081d6199/rtb-0bf2b5476a7fee7c9"
}
import {
  to = aws_route_table_association.public2_2c
  id = "subnet-0776ae1b0074673f3/rtb-0bf2b5476a7fee7c9"
}
import {
  to = aws_route_table_association.private1_2a
  id = "subnet-025eae99d89728a00/rtb-058eadff3c8ed4570"
}
import {
  to = aws_route_table_association.private3_2a
  id = "subnet-037f65b1f10cad853/rtb-058eadff3c8ed4570"
}
import {
  to = aws_route_table_association.private2_2c
  id = "subnet-07e817528f40582e4/rtb-0c5562e8a11dc4143"
}
import {
  to = aws_route_table_association.private4_2c
  id = "subnet-0298ce95f08db7c34/rtb-0c5562e8a11dc4143"
}
import {
  to = aws_route_table_association.private5_2a
  id = "subnet-0476d35e804dddf1f/rtb-002a230031020932d"
}
import {
  to = aws_route_table_association.private6_2c
  id = "subnet-0c28846b9d000850c/rtb-0e37a33af01492fee"
}

# --- 보안 그룹 ---
import {
  to = aws_security_group.bastion
  id = "sg-00294682a64d0e751"
}
import {
  to = aws_security_group.alb_public
  id = "sg-08f0c5e04f27a63f2"
}
import {
  to = aws_security_group.alb_internal
  id = "sg-0e57904932cd750c9"
}
import {
  to = aws_security_group.web
  id = "sg-0deeb61f28beef4ca"
}
import {
  to = aws_security_group.was
  id = "sg-0e3df15b6c658f161"
}
import {
  to = aws_security_group.db
  id = "sg-03fe8db85b8ac20a6"
}

# --- 진입 계층 ---
import {
  to = aws_lb.public
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:loadbalancer/app/test-Public-ALB/2a2b6cc29a7f91ce"
}
import {
  to = aws_lb.internal
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:loadbalancer/app/alb-internal-test/20aa87b0752aa8c0"
}
import {
  to = aws_lb_target_group.web
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:targetgroup/Targetgroup-web/6967a229da5789ea"
}
import {
  to = aws_lb_target_group.was
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:targetgroup/tg-internal-alb/e7c1dae7ffcd55ee"
}
import {
  to = aws_lb_listener.public_https
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:listener/app/test-Public-ALB/2a2b6cc29a7f91ce/15e27bd1afbd16e3"
}
import {
  to = aws_lb_listener.public_http
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:listener/app/test-Public-ALB/2a2b6cc29a7f91ce/c65bdbbdd8bd10ec"
}
import {
  to = aws_lb_listener.internal_http
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:listener/app/alb-internal-test/20aa87b0752aa8c0/e903df3d7f813ef2"
}
# 수동 등록 타깃(WEB-test-a · WAS-test-a)은 aws_lb_target_group_attachment 가 import 를 지원하지 않아 제외.
import {
  to = aws_acm_certificate.alb
  id = "arn:aws:acm:ap-northeast-2:723165663216:certificate/d9164227-4fee-498d-8ca4-2ae17c4994be"
}

# --- 컴퓨트 ---
import {
  to = aws_ami.web_apache
  id = "ami-081f6180df874677d"
}
import {
  to = aws_launch_template.web
  id = "lt-0c19a56346ccd3eff"
}
import {
  to = aws_autoscaling_group.web
  id = "web-test"
}
import {
  to = aws_autoscaling_policy.web_cpu
  id = "web-test/Target Tracking Policy"
}
import {
  to = aws_instance.was_test_a
  id = "i-0d7f99e2758122059"
}
import {
  to = aws_instance.web_test_a
  id = "i-02084ca917c81d58f"
}
import {
  to = aws_instance.bastion
  id = "i-0558ef697e0c42759"
}
import {
  to = aws_instance.web_ami
  id = "i-0c205c2e12ea8e389"
}
import {
  to = aws_ebs_volume.was_data
  id = "vol-07d20b27fb02490f6"
}
import {
  to = aws_volume_attachment.was_data
  id = "/dev/sdf:vol-07d20b27fb02490f6:i-0d7f99e2758122059"
}

# --- IAM ---
import {
  to = aws_iam_role.ec2
  id = "mc-ec2-role"
}
import {
  to = aws_iam_role.was
  id = "was-test-iam"
}
import {
  to = aws_iam_role.rds_monitoring
  id = "rds-monitoring-role"
}
import {
  to = aws_iam_instance_profile.ec2
  id = "mc-ec2-role"
}
import {
  to = aws_iam_instance_profile.was
  id = "was-test-iam"
}
import {
  to = aws_iam_role_policy_attachment.ec2_cloudwatch
  id = "mc-ec2-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
import {
  to = aws_iam_role_policy_attachment.ec2_ssm
  id = "mc-ec2-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
import {
  to = aws_iam_role_policy_attachment.was_rds
  id = "was-test-iam/arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}
import {
  to = aws_iam_role_policy_attachment.rds_monitoring
  id = "rds-monitoring-role/arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# --- 데이터 계층 ---
import {
  to = aws_db_subnet_group.main
  id = "petclinic-db-subnet-group"
}
import {
  to = aws_db_parameter_group.mysql_log
  id = "petclinic-mysql-log"
}
import {
  to = aws_db_instance.main
  id = "database-1"
}

# --- 스토리지 · 로그 ---
import {
  to = aws_s3_bucket.static
  id = "mc-static-image"
}
import {
  to = aws_s3_bucket_policy.static
  id = "mc-static-image"
}
import {
  to = aws_s3_bucket_public_access_block.static
  id = "mc-static-image"
}
import {
  to = aws_s3_bucket_server_side_encryption_configuration.static
  id = "mc-static-image"
}
import {
  to = aws_cloudwatch_log_group.rds_error
  id = "/aws/rds/instance/database-1/error"
}
import {
  to = aws_cloudwatch_log_group.rds_slowquery
  id = "/aws/rds/instance/database-1/slowquery"
}

# --- 엣지 계층 ---
import {
  to = aws_cloudfront_origin_access_control.static
  id = "E3LSPWJMKK7HIH"
}
import {
  to = aws_cloudfront_distribution.main
  id = "E1F6M0QDUUT8AG"
}
# 2026-09-19 21:19 KST 콘솔에서 만든 함수 — state 에 넣으려면 apply(import 1건, 변경 0) 가 한 번 필요하다
import {
  to = aws_cloudfront_function.home_to_landing
  id = "petclinic-home-to-landing"
}
import {
  provider = aws.us_east_1
  to       = aws_wafv2_web_acl.cloudfront
  id       = "3cc6a3dd-01f6-423b-a815-cd441599ef03/CreatedByCloudFront-2407cc5b/CLOUDFRONT"
}
import {
  provider = aws.us_east_1
  to       = aws_acm_certificate.cloudfront
  id       = "arn:aws:acm:us-east-1:723165663216:certificate/15b53573-85ae-48ca-a4d7-e75da5311fe8"
}
import {
  to = aws_route53_zone.main
  id = "Z08667423LQZPT6BSL30W"
}
import {
  to = aws_route53_record.app_a
  id = "Z08667423LQZPT6BSL30W_24petclinic.mission-critical.site_A"
}
import {
  to = aws_route53_record.app_aaaa
  id = "Z08667423LQZPT6BSL30W_24petclinic.mission-critical.site_AAAA"
}
import {
  to = aws_route53_record.acm_validation
  id = "Z08667423LQZPT6BSL30W__4291571fd8079830c5cc27aed5766391.mission-critical.site_CNAME"
}

# --- ALB 액세스 로그 버킷 (2026-09-21 콘솔 생성) ---
import {
  to = aws_s3_bucket.alb_logs
  id = "petclinic-log-alb"
}
import {
  to = aws_s3_bucket_public_access_block.alb_logs
  id = "petclinic-log-alb"
}
import {
  to = aws_s3_bucket_policy.alb_logs
  id = "petclinic-log-alb"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.alb_logs
  id = "petclinic-log-alb"
}

# --- Public ALB 443 superheader 규칙 (2026-09-21 콘솔 생성) ---
import {
  to = aws_lb_listener_rule.public_https_superheader
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:723165663216:listener-rule/app/test-Public-ALB/2a2b6cc29a7f91ce/15e27bd1afbd16e3/543d092d738ecd1d"
}

# --- 정적 버킷 버전 관리 (2026-09-21) ---
import {
  to = aws_s3_bucket_versioning.static
  id = "mc-static-image"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.static
  id = "mc-static-image"
}

# --- 2026-09-21 오후 콘솔 신규 (WAS ASG · WEB 요청수 스케일링 · SNS · 로그/WAF 버킷 · WAS 골든 AMI) ---
import {
  to = aws_launch_template.was
  id = "lt-03b9d84a0bb5d70d0"
}
import {
  to = aws_autoscaling_group.was
  id = "was-asg"
}
import {
  to = aws_autoscaling_policy.was_cpu
  id = "was-asg/Target Tracking Policy"
}
import {
  to = aws_autoscaling_policy.web_reqcount
  id = "web-test/cale-out-web-reqcount-20000~35000"
}
import {
  to = aws_cloudwatch_metric_alarm.web_reqcount_high
  id = "alarm-web-reqcount-high-20000"
}
import {
  to = aws_sns_topic.alerts
  id = "arn:aws:sns:ap-northeast-2:723165663216:mc-alerts"
}
import {
  to = aws_sns_topic_subscription.alerts_email
  id = "arn:aws:sns:ap-northeast-2:723165663216:mc-alerts:ea44ca0d-47cf-47df-99e8-bb7476bcc7fc"
}
import {
  to = aws_ami.was_golden
  id = "ami-0bd669bb5ad494b67"
}
import {
  to = aws_s3_bucket.central_logs
  id = "mc-logs-petclinic"
}
import {
  to = aws_s3_bucket_public_access_block.central_logs
  id = "mc-logs-petclinic"
}
import {
  provider = aws.us_east_1
  to       = aws_s3_bucket.waf_logs
  id       = "aws-waf-logs-petclinic-block"
}
import {
  provider = aws.us_east_1
  to       = aws_s3_bucket_public_access_block.waf_logs
  id       = "aws-waf-logs-petclinic-block"
}

# --- 2026-09-21 저녁 콘솔 신규 (WAS 골든 AMI v2 + 그 원본 인스턴스 was-gg2, semin) ---
import {
  to = aws_ami.was_golden_v2
  id = "ami-037c4fd127e1d9ac6"
}
import {
  to = aws_instance.was_gg2
  id = "i-0ea1eacda1a151ed9"
}

# --- 2026-09-21 오후·저녁 콘솔 신규 (관측: WAF 로깅 · CloudFront 표준 로그 v2 · 버킷 정책 2 · WAS 시크릿 읽기 정책) ---
import {
  provider = aws.us_east_1
  to       = aws_wafv2_web_acl_logging_configuration.cloudfront
  id       = "arn:aws:wafv2:us-east-1:723165663216:global/webacl/CreatedByCloudFront-2407cc5b/3cc6a3dd-01f6-423b-a815-cd441599ef03"
}
import {
  provider = aws.us_east_1
  to       = aws_s3_bucket_policy.waf_logs
  id       = "aws-waf-logs-petclinic-block"
}
import {
  provider = aws.us_east_1
  to       = aws_cloudwatch_log_delivery_source.cloudfront_access
  id       = "CreatedByCloudFront-E1F6M0QDUUT8AG-ACCESS_LOGS"
}
import {
  provider = aws.us_east_1
  to       = aws_cloudwatch_log_delivery_destination.cloudfront_access
  id       = "CF-E1F6M0QDUUT8AG-mc-logs-petclinic-petclinic-1789982984026"
}
import {
  provider = aws.us_east_1
  to       = aws_cloudwatch_log_delivery.cloudfront_access
  id       = "iVLg9LM2vvA0sUrm"
}
import {
  to = aws_s3_bucket_policy.central_logs
  id = "mc-logs-petclinic"
}
import {
  to = aws_iam_role_policy.was_read_rds_secret
  id = "was-test-iam:PetclinicReadRdsSecret"
}

# --- 2026-09-22 오후: 베스천 전용 역할(CloudWatch 만) + 새 규칙 로그 그룹 5개 (web v7 용 4 + 베스천 1) ---
import {
  to = aws_iam_role.bastion
  id = "bastion-role"
}
import {
  to = aws_iam_role_policy_attachment.bastion_cloudwatch
  id = "bastion-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
import {
  to = aws_iam_instance_profile.bastion
  id = "bastion-role"
}
import {
  to = aws_cloudwatch_log_group.web_apache_access
  id = "/petclinic/prod/web/apache/access"
}
import {
  to = aws_cloudwatch_log_group.web_apache_error
  id = "/petclinic/prod/web/apache/error"
}
import {
  to = aws_cloudwatch_log_group.web_ssh_access
  id = "/petclinic/prod/web/ssh/access"
}
import {
  to = aws_cloudwatch_log_group.web_bootstrap
  id = "/petclinic/prod/web/bootstrap"
}
import {
  to = aws_cloudwatch_log_group.bastion_ssh_secure
  id = "/petclinic/prod/bastion/ssh/secure"
}
import {
  to = aws_cloudwatch_log_group.bastion_system_messages
  id = "/petclinic/prod/bastion/system/messages"
}
