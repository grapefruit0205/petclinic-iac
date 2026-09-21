#!/bin/bash
# WAS 시작 템플릿 user data — 하이브리드 구성의 "설정·실행" 영역 (설치는 AMI: userdata/was-ami-build.sh).
# 부팅 때 하는 일: /data 마운트 → Secrets Manager 에서 DB 자격증명 → S3 의 범용 WAR 배치 + DB 설정 주입 → Tomcat 시작
#                 → CloudWatch Agent 설정(인라인 JSON)으로 실행. 빌드·설치가 없어 약 1분에 뜬다 → ASG 헬스체크 유예 120초.
set -uo pipefail
exec > >(tee -a /var/log/mc-userdata.log) 2>&1

REGION="ap-northeast-2"
WAR_S3_URI="s3://petclinic-artifacts-723165663216/petclinic/petclinic.war"   # -P MySQL 로 빌드한 범용 WAR (자격증명은 아래서 덮어씀)
DB_SECRET_ID="petclinic/prod/db/app"                                        # 앱 전용 계정(petclinic_app) 시크릿. 이름으로 조회하므로 ARN 뒤 난수를 몰라도 된다.
#    시크릿 키: username · password 필수, host · dbname 은 선택(있으면 아래서 그 값을 쓴다).
# ⚠️ admin 시크릿(rds!db-…)은 쓰지 않는다 — RDS 가 관리해 7일마다 교체되고, 마스터 권한이 앱에 통째로 간다. admin 교체는 켜둔 채로 둔다(사람만 쓴다).
#    이 앱 시크릿은 1단계(부팅 때 한 번 읽기)에서는 자동 교체를 끈 채로 둔다. 값을 바꾸면 ASG 인스턴스 새로 고침이 세트(떠 있는 인스턴스는 옛 값을 들고 있음).
#    2단계(Secrets Manager JDBC 드라이버, WAR 재빌드)로 가면 교체를 켜도 앱이 접속 때마다 스스로 읽는다 → 이 블록은 드라이버 설정 4줄로 바뀐다.
DB_HOST_DEFAULT="database-1.c6vkzvcvqawh.ap-northeast-2.rds.amazonaws.com"  # 시크릿에 host 키가 없을 때 쓰는 값 (RDS 직결 · Proxy 없음)
DB_NAME_DEFAULT="petclinic"

# ---- 1. /data (시작 템플릿 두 번째 볼륨 /dev/sdf, 암호화, DeleteOnTermination=true) ----
DEV=""
for i in $(seq 1 12); do DEV=$(readlink -f /dev/sdf 2>/dev/null || true); [ -b "$DEV" ] && break; echo "waiting /dev/sdf ($i/12)"; sleep 5; done
if [ -b "$DEV" ]; then
  blkid "$DEV" >/dev/null 2>&1 || mkfs.xfs -q "$DEV"
  mkdir -p /data
  grep -q " /data " /etc/fstab || echo "UUID=$(blkid -s UUID -o value "$DEV") /data xfs defaults,nofail 0 2" >> /etc/fstab
  mount -a
else
  echo "WARN: /dev/sdf not found — /data on root volume"; mkdir -p /data
fi
mkdir -p /data/logs/tomcat /data/dump /data/temp && chown -R tomcat:tomcat /data/logs /data/dump /data/temp

# ---- 2. DB 자격증명 ----
DB_SECRET=""
for i in $(seq 1 12); do
  DB_SECRET=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$DB_SECRET_ID" --query SecretString --output text 2>/dev/null) && [ -n "$DB_SECRET" ] && break
  echo "secret retry $i/12"; sleep 5
done
DB_USER=$(echo "$DB_SECRET" | jq -r .username)
DB_PASS=$(echo "$DB_SECRET" | jq -r .password)
DB_HOST=$(echo "$DB_SECRET" | jq -r '.host // empty');   [ -n "$DB_HOST" ] || DB_HOST="$DB_HOST_DEFAULT"
DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname // empty'); [ -n "$DB_NAME" ] || DB_NAME="$DB_NAME_DEFAULT"
JDBC_URL="jdbc:mysql://${DB_HOST}:3306/${DB_NAME}?useUnicode=true"
echo "db target: ${DB_USER}@${DB_HOST}/${DB_NAME}"
for i in $(seq 1 6); do
  mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" >/dev/null 2>&1 && { echo "DB login ok"; break; }
  echo "DB login retry $i/6"; sleep 10
done

# ---- 3. WAR 배치 (exploded) + DB 설정 주입 ----
# Tomcat 이 꺼진 상태에서 풀어 두고 설정 파일을 덮어쓴 뒤 시작한다. 빌드 시 박힌 [Change Me] 값은 여기서 전부 교체된다.
aws s3 cp --region "$REGION" "$WAR_S3_URI" /tmp/petclinic.war && echo "war downloaded" || { echo "WAR DOWNLOAD FAILED"; }
rm -rf /opt/tomcat/webapps/petclinic && mkdir -p /opt/tomcat/webapps/petclinic
unzip -q /tmp/petclinic.war -d /opt/tomcat/webapps/petclinic && rm -f /tmp/petclinic.war
cat > /opt/tomcat/webapps/petclinic/WEB-INF/classes/spring/data-access.properties <<PROPS
# generated at boot by user data — do not edit on the instance
jdbc.initLocation=classpath:db/mysql/schema.sql
jdbc.dataLocation=classpath:db/mysql/data.sql
jpa.showSql=false
jdbc.driverClassName=com.mysql.cj.jdbc.Driver
jdbc.url=${JDBC_URL}
jdbc.username=${DB_USER}
jdbc.password=${DB_PASS}
jpa.database=MYSQL
PROPS
chmod 640 /opt/tomcat/webapps/petclinic/WEB-INF/classes/spring/data-access.properties
chown -R tomcat:tomcat /opt/tomcat/webapps
unset DB_SECRET DB_PASS

# ---- 4. Tomcat ----
systemctl enable --now tomcat

# ---- 5. CloudWatch Agent — 이미지에 설치돼 있음. 설정 JSON 인라인 (Parameter Store 미사용, 2026-09-21 결정) ----
#   /data/logs/tomcat/catalina.out            → /petclinic/prod/was/tomcat/catalina (멀티라인: 날짜로 시작하는 줄이 새 이벤트)
#   /data/logs/tomcat/localhost_access_log.*  → /petclinic/prod/was/tomcat/access
#   /data/logs/tomcat/gc.log*                 → /petclinic/prod/was/jvm/gc
#   /var/log/mc-userdata.log                  → /petclinic/prod/was/bootstrap
# metrics: / 와 /data 디스크 사용률·메모리 → PetClinic/WAS
cat > /opt/aws/amazon-cloudwatch-agent/etc/cw-was.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "metrics": {
    "namespace": "PetClinic/WAS",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "disk": {
        "resources": [
          "/",
          "/data"
        ],
        "measurement": [
          "used_percent"
        ],
        "ignore_file_system_types": [
          "sysfs",
          "devtmpfs",
          "tmpfs"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/data/logs/tomcat/catalina.out",
            "log_group_name": "/petclinic/prod/was/tomcat/catalina",
            "log_stream_name": "{instance_id}",
            "timezone": "Local",
            "multi_line_start_pattern": "^(\\d{2}-[A-Za-z]{3}-\\d{4}|\\d{4}-\\d{2}-\\d{2})"
          },
          {
            "file_path": "/data/logs/tomcat/localhost_access_log.*.txt",
            "log_group_name": "/petclinic/prod/was/tomcat/access",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          },
          {
            "file_path": "/data/logs/tomcat/gc.log*",
            "log_group_name": "/petclinic/prod/was/jvm/gc",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          },
          {
            "file_path": "/var/log/mc-userdata.log",
            "log_group_name": "/petclinic/prod/was/bootstrap",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          }
        ]
      }
    }
  }
}
JSON
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-was.json \
  && echo "cwagent started (inline config)" || echo "CWAGENT CONFIG FAILED"

# ---- 6. 기동 확인 (tg-internal-alb 헬스체크 = /petclinic/ 200) ----
for i in $(seq 1 18); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/petclinic/ || true)
  [ "$code" = "200" ] && { echo "petclinic up after ~$((i*5))s"; break; }
  echo "waiting petclinic ($i/18) http=$code"; sleep 5
done
echo "userdata done"
