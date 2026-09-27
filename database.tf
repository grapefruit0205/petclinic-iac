# 데이터 계층 — RDS MySQL(Multi-AZ).
# RDS Proxy pet-proxy 는 아무도 안 써서(ClientConnections 0) 2026-09-22 08:55 KST 삭제 (CLI, kdt5).
# 프록시가 쓰던 IAM 역할·정책·로그 그룹도 같은 날 09:00 KST 삭제 완료 — 코드에 흔적 없음.
# 마스터 비밀번호: 처음엔 RDS 관리형 시크릿(rds!db-…)이었는데 2026-09-26 20:13 KST jaewoon 이 관리형을 끄고(그 시크릿은 RDS 가 20:14 즉시 삭제)
# 직접 정한 비밀번호로 바꿨다(21:13 한 번 더 변경). 그 값은 jaewoon 이 21:19 만든 일반 시크릿 RDS-Secret-key(아래)에 있고,
# WAS 역할이 그 시크릿을 읽는다(iam.tf). 비밀번호는 코드·state 에 두지 않는다 — password 를 비워 두면 provider 는 비교하지 않는다.

resource "aws_db_subnet_group" "main" {
  name        = "petclinic-db-subnet-group"
  description = "HIHIHIHIHIIHI"
  subnet_ids  = [aws_subnet.private5_2a.id, aws_subnet.private6_2c.id]
}

# 에러 로그 상세 + 슬로우 쿼리(2초) 를 FILE 로 남긴다 → CloudWatch 로그 내보내기 대상.
resource "aws_db_parameter_group" "mysql_log" {
  name        = "petclinic-mysql-log"
  family      = "mysql8.0"
  description = "123123"

  # 2026-09-26 15:17 KST jaewoon 콘솔: 커밋마다 디스크에 바로 쓰지 않고 1초에 한 번 모아서 씀 (쓰기 부하 완화).
  # 대신 DB 서버가 갑자기 죽으면 마지막 1초 안의 커밋이 사라질 수 있다.
  parameter {
    name         = "innodb_flush_log_at_trx_commit"
    value        = "2"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_error_verbosity"
    value        = "2"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "immediate"
  }
  parameter {
    name         = "long_query_time"
    value        = "2"
    apply_method = "immediate"
  }
  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }
}

# 감사 로그(MariaDB Audit Plugin) — 2026-09-24 14:33 KST jaewoon 콘솔 생성, 14:37 플러그인 추가, 14:56 database-1 에 연결.
# 설정은 전부 기본값: SERVER_AUDIT_EVENTS = CONNECT,QUERY · 사용자 제한 없음(전체) · 쿼리 로그 1,024자.
# 그래서 option_settings 를 적지 않는다 (provider 는 적은 설정만 비교한다). 켜진 뒤로 DB CPU 가 늘었다 — 부하 테스트 9/24 15:05 회차부터.
resource "aws_db_option_group" "audit" {
  name                     = "mysql80-custom-auditlogs"
  option_group_description = "Custom option group for RDS MySQL 8.0.44"
  engine_name              = "mysql"
  major_engine_version     = "8.0"

  option {
    option_name = "MARIADB_AUDIT_PLUGIN"
  }
}

# 2026-09-26 jaewoon 콘솔(읽기 복제본 준비): 19:12 이름 database-1 → database-read-only · 최대 스토리지 1000 → 250 · Multi-AZ 끔,
# 19:59 이름 database · Multi-AZ 다시 켬, 20:13 비밀번호 방식 변경(위), 20:33 복제본 db-readonly 생성(아래).
# 이름이 바뀌면 엔드포인트도 바뀐다(database-1.c6vk… → database.c6vk…). 그날 21:30~01:47 WAS 가 ELB 헬스 체크에 28번 실패해 교체됐고
# 01:47~03:49 는 WAS 0대 — semin 이 이미지 v6 · 시작 템플릿 v7 로 복구(compute.tf).
resource "aws_db_instance" "main" {
  identifier     = "database"
  engine         = "mysql"
  engine_version = "8.0.44"
  instance_class = "db.t3.small"

  db_name  = "petclinic"
  username = "admin"
  port     = 3306

  allocated_storage     = 200
  max_allocated_storage = 250 # 2026-09-26 19:12 jaewoon 1000 → 250 (자동 확장 상한)
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125
  storage_encrypted     = true
  kms_key_id            = "arn:aws:kms:ap-northeast-2:723165663216:key/d1e1bfc1-b343-4681-a1fe-d60c38e4863e"

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.mysql_log.name
  option_group_name      = aws_db_option_group.audit.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  # 자동 백업 7일 — 2026-09-26 18:38 KST jaewoon 콘솔에서 0 → 7 (시점 복구 가능). 매일 스냅샷은 AWS Backup 도 따로 만든다(아래 aws_backup_plan.rds).
  backup_retention_period = 7
  backup_window           = "13:45-14:15"
  maintenance_window      = "mon:13:01-mon:13:31"
  copy_tags_to_snapshot   = false
  deletion_protection     = true # 2026-09-25 00:56 KST jaewoon 콘솔에서 켬

  auto_minor_version_upgrade = false
  # audit 내보내기는 9/24 14:56 켰다가 2026-09-25 00:56 KST jaewoon 이 끔 — 옵션 그룹(감사 플러그인)은 그대로라 감사 로그는 DB 안에만 남는다.
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  monitoring_interval             = 0 # 향상된 모니터링 꺼짐 (rds-monitoring-role 미사용)
  performance_insights_enabled    = false

  # import 시 provider 가 true 로 채운다. destroy 시 최종 스냅샷을 안 남긴다는 뜻이라 prevent_destroy 로 막는다.
  skip_final_snapshot = true

  lifecycle {
    prevent_destroy = true
  }
}

# 읽기 복제본 — 2026-09-26 20:33 KST jaewoon 콘솔 생성. database 에서 비동기 복제, 2a 한 곳(Multi-AZ 아님).
# 엔드포인트 db-readonly.c6vk…. 엔진·사용자·DB 이름은 원본에서 물려받아 적지 않는다.
# 원본과 다른 점: 향상된 모니터링 60초(rds-monitoring-role) · 마이너 버전 자동 업그레이드 켬 · 최대 스토리지 1000 · 자동 백업 0 · 삭제 보호 꺼짐.
resource "aws_db_instance" "replica" {
  identifier          = "db-readonly"
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = "db.t3.small"
  availability_zone   = "ap-northeast-2a"

  allocated_storage     = 200
  max_allocated_storage = 1000
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125
  storage_encrypted     = true
  kms_key_id            = "arn:aws:kms:ap-northeast-2:723165663216:key/d1e1bfc1-b343-4681-a1fe-d60c38e4863e"

  # 서브넷 그룹은 원본(petclinic-db-subnet-group)을 물려받는다. 같은 리전 복제본에 적으면 provider 가 source 를 ARN 으로 요구해 적지 않는다.
  multi_az               = false
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  port                   = 3306
  parameter_group_name   = aws_db_parameter_group.mysql_log.name
  option_group_name      = aws_db_option_group.audit.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  backup_retention_period = 0
  backup_window           = "13:45-14:15"
  maintenance_window      = "mon:13:01-mon:13:31"
  copy_tags_to_snapshot   = false
  deletion_protection     = false

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = false

  skip_final_snapshot = true
}

# DB 마스터 비밀번호 보관 — 2026-09-26 21:19 KST jaewoon 콘솔 생성. 일반 시크릿(자동 교체 없음, 기본 키 aws/secretsmanager).
# 값(버전)은 코드·state 에 두지 않는다 — 시크릿 껍데기만 관리.
resource "aws_secretsmanager_secret" "rds_app" {
  name        = "RDS-Secret-key"
  description = "RDS-Secret-key"
}

# --- AWS Backup (2026-09-25 16:00~16:06 KST jaewoon 콘솔) ---
# 매일 03:00 KST 스냅샷을 35일 보관. 첫 백업 9/25 성공. (9/26 부터는 RDS 자동 백업 7일도 켜져 있어 백업이 두 겹이다.)
# 금고 암호화 키는 AWS 관리형 alias/aws/backup.
resource "aws_backup_vault" "rds" {
  name        = "rds-backup-vault"
  kms_key_arn = "arn:aws:kms:ap-northeast-2:723165663216:key/0849470e-6009-4c91-a002-9e1e181e70e2"
}

# 매일 03:00 KST 시작(8시간 안), 24시간 안에 끝, 35일 보관.
resource "aws_backup_plan" "rds" {
  name = "rds-backup-prod-daily"

  rule {
    rule_name                    = "rds-backup"
    target_vault_name            = aws_backup_vault.rds.name
    schedule                     = "cron(0 3 ? * * *)"
    schedule_expression_timezone = "Asia/Seoul"
    start_window                 = 480
    completion_window            = 1440
    enable_continuous_backup     = false

    lifecycle {
      delete_after = 35
    }
  }

  # 콘솔이 기본으로 넣은 S3 백업 옵션(BackupACLs·BackupObjectTags enabled)이 실물에 있지만,
  # 지금 provider 는 advanced_backup_setting 에 EC2 만 받는다 → 적지 않고 무시한다. (이 계획은 S3 를 백업하지 않는다)
  lifecycle {
    ignore_changes = [advanced_backup_setting]
  }
}

# 대상: 계정의 모든 RDS DB 인스턴스 — 지금은 database 와 복제본 db-readonly 둘 다 (9/27 04:05·04:54 둘 다 스냅샷됨).
resource "aws_backup_selection" "rds" {
  name         = "rds-prod-assignment"
  plan_id      = aws_backup_plan.rds.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["arn:aws:rds:*:*:db:*"]
}
