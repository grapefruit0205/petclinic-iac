#!/bin/bash
# web 시작 템플릿 v7 — v6 + access 로그 첫 칸에 X-Forwarded-For(사용자 IP) · logrotate 3일 · 로그 그룹 이름 규칙 · 디스크 지표.
# 단순화 결정(2026-09-21): AMI 는 v6 그대로(web-appache), 에이전트는 v6 처럼 부팅 시 dnf 설치, 설정 JSON 은 이 파일 안에 인라인
# (Parameter Store 미사용). 설정은 시작 템플릿에만 둔다 — 바꾸려면 새 템플릿 버전 + 리프레시.
set -uo pipefail
exec > >(tee -a /var/log/mc-userdata.log) 2>&1
INTERNAL_ALB="internal-alb-internal-test-908324103.ap-northeast-2.elb.amazonaws.com"
# CloudFront 가 ALB 오리진 요청에 붙이는 커스텀 헤더 값 (CloudFront 배포 E1F6M0QDUUT8AG 의 origin custom_header 와 같아야 한다)
CF_SECRET="mypetcliniczzang"
# httpd.conf 기본 CustomLog 는 같은 파일(logs/access_log)에 필터 없이 또 쓴다 → 헬스체크가 그대로 남고
# 일반 요청은 두 줄. 기본 것을 끄고 아래 petclinic.conf 의 CustomLog(env=!nolog) 하나만 다.
sed -i 's|^\(\s*\)CustomLog "logs/access_log" combined|\1#CustomLog "logs/access_log" combined   # disabled: conf.d/petclinic.conf logs with health-check filter|' /etc/httpd/conf/httpd.conf
cat > /etc/httpd/conf.d/petclinic.conf <<CONF
ProxyPreserveHost On
RewriteEngine On
# CloudFront 를 거치지 않은 요청(ALB DNS 직접 접근)은 403 — superheader 가 없거나 다르면 차단.
# ALB 헬스체크(/health.html)는 CloudFront 를 안 거치므로 예외. 이 예외를 빼면 타깃이 전부 unhealthy 가 된다.
RewriteCond %{REQUEST_URI} !^/health\.html$
RewriteCond %{HTTP:superheader} !=${CF_SECRET}
RewriteRule ^ - [F]
RewriteRule ^/petclinic$ /petclinic/ [R=301,L]
ProxyPass        /petclinic/ http://${INTERNAL_ALB}/petclinic/
ProxyPassReverse /petclinic/ http://${INTERNAL_ALB}/petclinic/
# 로그 첫 칸 = X-Forwarded-For(사용자 IP, CloudFront 경유). 직접 접근(403 스캐너)은 "-". %D = 처리 시간(µs).
LogFormat "%{X-Forwarded-For}i %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %D" xff
SetEnvIf Request_URI "^/health.html$" nolog
CustomLog /var/log/httpd/access_log xff env=!nolog
CONF
echo ok > /var/www/html/health.html
# 로컬 보관 3일 (CloudWatch 로 실시간 전송하므로 버퍼·디버깅용). 패키지 기본은 weekly·4개.
cat > /etc/logrotate.d/httpd <<'ROT'
/var/log/httpd/*log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/systemctl reload httpd.service > /dev/null 2>/dev/null || true
    endscript
}
ROT
setsebool -P httpd_can_network_connect 1 || true
apachectl configtest && systemctl enable --now httpd && systemctl restart httpd

# --- CloudWatch Agent: 부팅 시 설치(약 30초) → 설정 JSON 을 파일로 쓰고 실행 ---
dnf install -y amazon-cloudwatch-agent
# 어느 파일을 → 어느 로그 그룹으로 보낼지. 그룹은 클래스·보존기간을 지정해 미리 만들어 둔다 (에이전트가 만들면 STANDARD·무기한).
#   /var/log/httpd/access_log   → /petclinic/prod/web/apache/access  (30일, IA)      xff 포맷: 첫 칸 사용자 IP, 마지막 %D 처리시간
#   /var/log/httpd/error_log    → /petclinic/prod/web/apache/error   (90일, STANDARD) 멀티라인: "[" 로 시작하는 줄이 새 이벤트
#   /var/log/secure             → /petclinic/prod/web/ssh/access     (90일, IA)
#   /var/log/mc-userdata.log    → /petclinic/prod/web/bootstrap      (14일, STANDARD) 이 스크립트의 출력
# metrics: 루트 디스크 사용률·메모리 → 네임스페이스 PetClinic/WEB (디스크 80% 알람용)
cat > /opt/aws/amazon-cloudwatch-agent/etc/cw-web.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "PetClinic/WEB",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "disk": {
        "resources": [
          "/"
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
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/petclinic/prod/web/apache/access",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "/petclinic/prod/web/apache/error",
            "log_stream_name": "{instance_id}",
            "timezone": "Local",
            "multi_line_start_pattern": "^\\["
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/petclinic/prod/web/ssh/access",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          },
          {
            "file_path": "/var/log/mc-userdata.log",
            "log_group_name": "/petclinic/prod/web/bootstrap",
            "log_stream_name": "{instance_id}",
            "timezone": "Local"
          }
        ]
      }
    }
  }
}
JSON
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-web.json \
  && echo "cwagent started (inline config)" || echo "CWAGENT CONFIG FAILED"
echo "userdata done"
