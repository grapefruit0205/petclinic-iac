#!/bin/bash
sudo dnf update -y
sudo dnf install -y httpd
sudo systemctl enable --now httpd
cd /tmp
curl -fL https://aws-largeobjects.s3.ap-northeast-2.amazonaws.com/KDT-PROJECT/index.html -o index.html
sudo cp index.html /var/www/html/index.html
sudo chmod 644 /var/www/html/index.html