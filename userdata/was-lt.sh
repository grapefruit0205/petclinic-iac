#!/bin/bash
set -euxo pipefail

DATA_MOUNT=/data
mkdir -p "$DATA_MOUNT"

ROOT_SOURCE=$(findmnt -n -o SOURCE /)
ROOT_PARENT=$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)
ROOT_DISK=""

if [ -n "$ROOT_PARENT" ]; then
    ROOT_DISK="/dev/$ROOT_PARENT"
fi

DATA_DEV=$(lsblk -dnpo NAME,TYPE,MOUNTPOINT | \
    awk -v root="$ROOT_DISK" \
    '$2 == "disk" && $1 != root && $3 == "" {print $1; exit}')

if [ -z "${DATA_DEV:-}" ]; then
    lsblk -f
    exit 1
fi

if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
    mkfs.xfs -f "$DATA_DEV"
fi

DATA_UUID=$(blkid -s UUID -o value "$DATA_DEV")

if ! grep -q "UUID=$DATA_UUID $DATA_MOUNT " /etc/fstab; then
    echo "UUID=$DATA_UUID $DATA_MOUNT xfs defaults,nofail 0 2" >> /etc/fstab
fi

systemctl daemon-reload
mount "$DATA_MOUNT" || mount -a

mkdir -p /data/dump /data/logs
chown -R tomcat:tomcat /data/dump /data/logs
chmod 0750 /data/dump /data/logs

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c ssm:/petclinic/cwagent/was \
  -s

systemctl enable amazon-cloudwatch-agent
systemctl enable tomcat
systemctl start tomcat