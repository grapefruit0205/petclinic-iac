#!/bin/bash
# web 시작 템플릿 v13 — v12 + Apache 작업 스레드를 부팅 때 1024개 미리 띄움 (2026-09-24). 그 밖에는 v12 와 같다.
# S5 단계 상승(9/24 15:05~15:18 KST) 502 2,023건은 전부 공개 ALB 가 만든 ELB 502(대상 web, target_status '-', 요청 보낸 뒤 4~67 ms 만에 끊김, Apache 로그 0).
# 매분 00초에 DB 를 쓰는 요청만 잠깐 느려지고(부하 없을 때 +0.1~0.3초, 부하 중 최대 1.7초 — DB 안 쓰는 /owners/find 는 그대로),
# 그동안 web 한 대에 요청이 수백 개 쌓인다. 기본값(스레드 25개짜리 프로세스, 평소 75개만 떠 있고 초당 조금씩 늘림)으로는
# 프로세스 하나의 스레드가 금방 다 차고, event MPM 은 그러면 그 프로세스의 쉬는 keep-alive 연결을 닫는다(공식 문서 AsyncRequestWorkerFactor 절)
# → ALB 가 막 요청을 보낸 연결이 끊겨 502. 스레드를 처음부터 넉넉히 띄워 두면 요청은 잠깐 기다릴 뿐 끊기지 않는다.
# 1000 RPS 에서도 같은 현상: 3차(v11) 9건 12:39:00·01·12:40:02, v12 뒤 1단계 8건 15:06:00·02·15:07:00 — 전부 00~02초.
#
# (v12) v11 + KeepAliveTimeout 65.
# S5 3차(9/24 12:39:00~01 · 12:40:02 KST) 502 9건은 공개 ALB 가 직접 만든 ELB 502(대상 web, target_status '-', Apache error 로그 0).
# Apache(event MPM) 는 KeepAliveTimeout 기본 5초라 쉬는 연결을 5초 만에 닫는데 공개 ALB idle timeout 은 60초 —
# ALB 가 Apache 가 막 닫은 연결에 요청을 보내면 502. AWS 권장대로 대상 쪽 유지 시간을 ALB 보다 길게(65초) 둔다.
# (v11 의 ttl=55 는 뒤 구간 Apache → 내부 ALB. 두 구간 규칙은 같다 — 받는 쪽(뒤)이 보내는 쪽(앞)보다 연결을 늦게 닫을 것.)
#
# (v11) v10 + 내부 ALB 프록시 연결 ttl=55 (2026-09-24).
# 부하 테스트 S5 재실행(9/24 02:13:00 KST)에서 POST 1건 502: Apache 가 내부 ALB 와의 keep-alive 연결을 재사용했는데
# ALB 가 이미 닫은 연결이라 "AH01102: error reading status line from remote server" → Apache 가 2 ms 만에 502 (내부 ALB 에는 기록 없음).
# 내부 ALB idle timeout 이 60초라, Apache 가 55초 넘게 쉰 연결은 다시 쓰지 않고 먼저 정리하게 한다.
#
# (v10) v9 의 Parameter Store 방식을 되돌려 설정 JSON 을 다시 이 파일 안에 인라인(v7 방식) + 그룹별 retention_in_days.
# 2026-09-23 결정: web 은 v8 부터 프로파일이 CloudWatchAgentServerPolicy 뿐이라 Session Manager·Run Command 가 없다 → 파라미터를 고쳐도
# 결국 리프레시가 필요해 Parameter Store 의 이점이 없고, 부팅 때 외부 의존(파라미터가 없거나 JSON 이 깨지면 새 서버 로그·지표 누락)만 는다.
# 부하 테스트 스케일 아웃 서버도 템플릿만으로 로그가 나가게 인라인. 설정을 바꾸려면 새 템플릿 버전 + 리프레시. Apache 부분은 v7~v9 와 같다.
set -uo pipefail
exec > >(tee -a /var/log/mc-userdata.log) 2>&1
INTERNAL_ALB="internal-alb-internal-test-908324103.ap-northeast-2.elb.amazonaws.com"
# CloudFront 가 ALB 오리진 요청에 붙이는 커스텀 헤더 값 (CloudFront 배포 E1F6M0QDUUT8AG 의 origin custom_header 와 같아야 한다)
CF_SECRET="__CF_SECRET__"
# httpd.conf 기본 CustomLog 는 같은 파일(logs/access_log)에 필터 없이 또 쓴다 → 헬스체크가 그대로 남고
# 일반 요청은 두 줄. 기본 것을 끄고 아래 petclinic.conf 의 CustomLog(env=!nolog) 하나만 다.
sed -i 's|^\(\s*\)CustomLog "logs/access_log" combined|\1#CustomLog "logs/access_log" combined   # disabled: conf.d/petclinic.conf logs with health-check filter|' /etc/httpd/conf/httpd.conf
cat > /etc/httpd/conf.d/petclinic.conf <<CONF
ProxyPreserveHost On
# 공개 ALB idle timeout(60초)보다 길게 — Apache 가 먼저 닫은 연결을 ALB 가 재사용해 ELB 502 가 나는 것을 막는다 (v12).
# event MPM 은 쉬는 연결을 작업 스레드 없이 들고 있어서 65초로 늘려도 스레드가 모자라지 않는다.
KeepAliveTimeout 65
# v13: 작업 스레드 = 16 프로세스 × 64 = 1024 를 부팅 때 전부 띄우고(StartServers = ServerLimit) 줄이지 않는다(MaxSpareThreads = MaxRequestWorkers).
# 1024 = S5 5단계 00초에 web 한 대에 쌓인 요청 약 730(초당 약 290 × 약 2.5초, 추정)보다 크게. 기본값은 16 × 25 = 400 이고 평소 75개만 떠 있다.
# 메모리: 스레드 230개일 때 httpd RSS 합 56 MB(9/24 실측) → 1024개면 약 250 MB 로 추정, t3.small 여유 약 1.5 GB.
<IfModule mpm_event_module>
    ServerLimit           16
    ThreadLimit           64
    ThreadsPerChild       64
    MaxRequestWorkers   1024
    StartServers          16
    MinSpareThreads       64
    MaxSpareThreads     1024
</IfModule>
RewriteEngine On
# CloudFront 를 거치지 않은 요청(ALB DNS 직접 접근)은 403 — superheader 가 없거나 다르면 차단.
# ALB 헬스체크(/health.html)는 CloudFront 를 안 거치므로 예외. 이 예외를 빼면 타깃이 전부 unhealthy 가 된다.
RewriteCond %{REQUEST_URI} !^/health\.html$
RewriteCond %{HTTP:superheader} !=${CF_SECRET}
RewriteRule ^ - [F]
RewriteRule ^/petclinic$ /petclinic/ [R=301,L]
# ttl=55: 내부 ALB idle timeout(60초)보다 짧게 — ALB 가 닫은 연결을 재사용해 502(AH01102)가 나는 것을 막는다 (v11)
ProxyPass        /petclinic/ http://${INTERNAL_ALB}/petclinic/ ttl=55
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
# rsyslog: AL2023 은 기본으로 없어서 /var/log/secure 가 안 생긴다 (베스천에서 2026-09-22 실측). ssh/access 로그 그룹용.
dnf install -y rsyslog amazon-cloudwatch-agent
systemctl enable --now rsyslog
# 어느 파일을 → 어느 로그 그룹으로 보낼지 (보존기간 = retention_in_days). 그룹이 없으면 에이전트가 STANDARD 로 만들고 보존기간까지 걸고,
# 이미 있으면 보존기간을 이 값으로 맞춘다 → 그룹을 미리 만들 필요 없음 (2026-09-23 v9 에서 실측). 태그는 에이전트가 못 붙인다.
#   /var/log/httpd/access_log   → /petclinic/prod/web/apache/access  (30일)  xff 포맷: 첫 칸 사용자 IP, 마지막 %D 처리시간
#   /var/log/httpd/error_log    → /petclinic/prod/web/apache/error   (90일)  멀티라인: "[" 로 시작하는 줄이 새 이벤트
#   /var/log/secure             → /petclinic/prod/web/ssh/access     (90일)
#   /var/log/mc-userdata.log    → /petclinic/prod/web/bootstrap      (14일)  이 스크립트의 출력
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
            "timezone": "Local",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "/petclinic/prod/web/apache/error",
            "log_stream_name": "{instance_id}",
            "timezone": "Local",
            "multi_line_start_pattern": "^\\[",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/petclinic/prod/web/ssh/access",
            "log_stream_name": "{instance_id}",
            "timezone": "Local",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/mc-userdata.log",
            "log_group_name": "/petclinic/prod/web/bootstrap",
            "log_stream_name": "{instance_id}",
            "timezone": "Local",
            "retention_in_days": 14
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
