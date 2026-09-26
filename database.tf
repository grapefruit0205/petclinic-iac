# 데이터 계층 — RDS MySQL(Multi-AZ).
# RDS Proxy pet-proxy 는 아무도 안 써서(ClientConnections 0) 2026-09-22 08:55 KST 삭제 (CLI, kdt5).
# 프록시가 쓰던 IAM 역할·정책·로그 그룹도 같은 날 09:00 KST 삭제 완료 — 코드에 흔적 없음.
# 마스터 비밀번호는 RDS 관리형 시크릿(rds!db-…)이다. provider 는 import 시 manage_master_user_password 를
# 읽지 않으므로 코드에 넣으면 plan 에 변경으로 잡힌다 — 그래서 비워 둔다. 시크릿 ARN 은 master_user_secret 로 참조.

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

resource "aws_db_instance" "main" {
  identifier     = "database-1"
  engine         = "mysql"
  engine_version = "8.0.44"
  instance_class = "db.t3.small"

  db_name  = "petclinic"
  username = "admin"
  port     = 3306

  allocated_storage     = 200
  max_allocated_storage = 1000
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

  # 자동 백업 0일 = RDS 자체 백업은 없다. 대신 2026-09-25 jaewoon 이 AWS Backup 으로 매일 백업(아래 aws_backup_plan.rds).
  backup_retention_period = 0
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

# --- AWS Backup (2026-09-25 16:00~16:06 KST jaewoon 콘솔) ---
# RDS 자동 백업(backup_retention_period)은 0 이라, 매일 스냅샷을 AWS Backup 이 대신 만든다. 첫 백업 9/25 성공.
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

# 대상: 계정의 모든 RDS DB 인스턴스 (지금은 database-1 하나).
resource "aws_backup_selection" "rds" {
  name         = "rds-prod-assignment"
  plan_id      = aws_backup_plan.rds.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["arn:aws:rds:*:*:db:*"]
}
