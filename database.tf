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
  option_group_name      = "default:mysql-8-0"
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  # ⚠️ 자동 백업 0일 = 백업 없음. 수동 스냅샷도 없다.
  backup_retention_period = 0
  backup_window           = "13:45-14:15"
  maintenance_window      = "mon:13:01-mon:13:31"
  copy_tags_to_snapshot   = false
  deletion_protection     = false

  auto_minor_version_upgrade      = false
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"] # audit 은 옵션 그룹에 플러그인이 없어 실제 로그 그룹이 없다
  monitoring_interval             = 0                               # 향상된 모니터링 꺼짐 (rds-monitoring-role 미사용)
  performance_insights_enabled    = false

  # import 시 provider 가 true 로 채운다. destroy 시 최종 스냅샷을 안 남긴다는 뜻이라 prevent_destroy 로 막는다.
  skip_final_snapshot = true

  lifecycle {
    prevent_destroy = true
  }
}
