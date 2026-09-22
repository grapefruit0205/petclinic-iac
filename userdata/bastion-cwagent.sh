#!/bin/bash
# 베스천 CloudWatch Agent 설치·설정 (2026-09-22). 인스턴스 안에서 `bash bastion-cwagent.sh` 로 1회 실행.
# 전제: 인스턴스 프로파일 bastion-role (CloudWatchAgentServerPolicy), 로그 그룹 /petclinic/prod/bastion/ssh/secure 가 먼저 있어야 한다.
# 베스천을 새로 만들 땐 이 파일을 user data 로 넣으면 같은 결과.
set -euo pipefail

# AL2023 은 rsyslog 가 없어 SSH 로그가 journald 에만 남고 /var/log/secure 가 생기지 않는다 → 에이전트가 읽을 파일이 없다.
# rsyslog 를 켜면 journald 의 authpriv 가 /var/log/secure 로 써진다 (2026-09-22 실측: 설치 전엔 스트림이 아예 안 생겼음).
sudo dnf install -y rsyslog amazon-cloudwatch-agent
sudo systemctl enable --now rsyslog

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/cw-bastion.json >/dev/null <<'JSON'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/secure", "log_group_name": "/petclinic/prod/bastion/ssh/secure", "log_stream_name": "{instance_id}", "timezone": "UTC" }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "PetClinic/Bastion",
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "metrics_collected": {
      "mem":  { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 },
      "disk": { "measurement": ["used_percent"], "resources": ["/"], "metrics_collection_interval": 60 }
    }
  }
}
JSON

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-bastion.json -s

sleep 3
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status | grep -E '"status"|"version"'
sudo tail -4 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
