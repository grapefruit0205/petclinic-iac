#!/bin/bash
set -uo pipefail
exec > >(tee -a /var/log/mc-userdata.log) 2>&1
INTERNAL_ALB="internal-alb-internal-test-908324103.ap-northeast-2.elb.amazonaws.com"
# httpd.conf 기본 CustomLog 는 같은 파일(logs/access_log)에 필터 없이 또 쓴다 → 헬스체크가 그대로 남고
# 일반 요청은 두 줄. 기본 것을 끄고 아래 petclinic.conf 의 CustomLog(env=!nolog) 하나만 다.
sed -i 's|^\(\s*\)CustomLog "logs/access_log" combined|\1#CustomLog "logs/access_log" combined   # disabled: conf.d/petclinic.conf logs with health-check filter|' /etc/httpd/conf/httpd.conf
cat > /etc/httpd/conf.d/petclinic.conf <<CONF
ProxyPreserveHost On
RewriteEngine On
RewriteRule ^/petclinic$ /petclinic/ [R=301,L]
ProxyPass        /petclinic/ http://${INTERNAL_ALB}/petclinic/
ProxyPassReverse /petclinic/ http://${INTERNAL_ALB}/petclinic/
SetEnvIf Request_URI "^/health.html$" nolog
CustomLog /var/log/httpd/access_log combined env=!nolog
CONF
echo ok > /var/www/html/health.html
setsebool -P httpd_can_network_connect 1 || true
apachectl configtest && systemctl enable --now httpd && systemctl restart httpd

# --- CloudWatch Agent ---
dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/cw-web.json <<'JSON'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/httpd/access_log", "log_group_name": "/petclinic/web/access", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/httpd/error_log",  "log_group_name": "/petclinic/web/error",  "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
JSON
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-web.json -s