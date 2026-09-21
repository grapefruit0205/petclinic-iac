#!/bin/bash
# WAS 골든 AMI 굽기 (1회, WAS 담당) — 하이브리드 구성의 "설치" 영역.
# AL2023 임시 인스턴스에 이 스크립트를 실행한 뒤 CreateImage → AMI 이름 예: was-tomcat9-corretto8-v1
# 여기에 넣는 것: JDK · Tomcat · CloudWatch Agent 설치, 정적 설정(access 로그 회전, GC 로그, logrotate, systemd 유닛).
# 여기에 넣지 않는 것: WAR · DB 자격증명 · 에이전트 설정(→ SSM) · /data 마운트(→ user data). 에이전트를 실행하지도 않는다.
set -euo pipefail
exec > >(tee -a /var/log/mc-ami-build.log) 2>&1
TOMCAT_VER="9.0.121"

dnf install -y java-1.8.0-amazon-corretto-devel unzip jq mariadb105 amazon-cloudwatch-agent

# ---- Tomcat ----
cd /tmp && curl -fsSLO "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz"
mkdir -p /opt/tomcat && tar xzf "apache-tomcat-${TOMCAT_VER}.tar.gz" -C /opt/tomcat --strip-components=1
id tomcat >/dev/null 2>&1 || useradd -r -m -d /opt/tomcat -s /sbin/nologin tomcat
rm -rf /opt/tomcat/webapps/*                     # ROOT·docs·examples·manager·host-manager 제거 (실물 WAS 엔 남아 있음)
rm -rf /opt/tomcat/logs && ln -s /data/logs/tomcat /opt/tomcat/logs   # /data 는 user data 가 마운트한다

# access 로그: 날짜별 파일 + 3일 지나면 Tomcat 이 스스로 삭제(maxDays) + ALB 뒤라 실제 클라이언트 IP(XFF)·처리시간(%D) 기록
sed -i 's|prefix="localhost_access_log" suffix=".txt"|prefix="localhost_access_log" suffix=".txt" maxDays="3"|; s|pattern="%h %l %u %t &quot;%r&quot; %s %b"|pattern="%{X-Forwarded-For}i %h %l %u %t \&quot;%r\&quot; %s %b %D"|' /opt/tomcat/conf/server.xml
grep -q 'maxDays="3"' /opt/tomcat/conf/server.xml || { echo "server.xml AccessLogValve 수정 실패"; exit 1; }

# catalina.out 은 Tomcat 이 회전하지 않는다 → logrotate (매일, 3일, 압축, copytruncate 로 열린 파일 유지)
cat > /etc/logrotate.d/tomcat <<'ROT'
/data/logs/tomcat/catalina.out {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
ROT

# systemd — 실물 WAS-test-a 유닛 + GC 로그(회전 3개×20M). 부팅 순서상 /data 마운트 뒤에만 뜨도록 RequiresMountsFor.
# enable 하지 않는다: user data 가 /data 마운트·WAR 배치·DB 설정을 끝낸 뒤 enable --now 한다.
cat > /etc/systemd/system/tomcat.service <<'UNIT'
[Unit]
Description=Apache Tomcat Web Application Container
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/data
[Service]
Type=simple
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto.x86_64/jre"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_TMPDIR=/opt/tomcat/temp"
Environment="CATALINA_OPTS=-Xms512m -Xmx1024m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/dump -Xloggc:/data/logs/tomcat/gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=3 -XX:GCLogFileSize=20M"
ExecStart=/opt/tomcat/bin/catalina.sh run
Restart=on-failure
RestartSec=10
SuccessExitStatus=143
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
chown -R tomcat:tomcat /opt/tomcat

# AMI 로 굽기 전 정리 — 인스턴스 고유 정보가 이미지에 남지 않게
cloud-init clean --logs || true
rm -f /var/log/mc-ami-build.log.bak
echo "AMI build done: java=$(java -version 2>&1 | head -1) tomcat=${TOMCAT_VER} cwagent=$(rpm -q amazon-cloudwatch-agent)"
