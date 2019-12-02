#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# GrayLog server installation script
# Reference - https://docs.graylog.org/en/3.1/pages/installation/os/centos.html

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

#
# Base installation software
curl -sfL https://raw.githubusercontent.com/m0zgen/run-cent/master/run.sh | sh

# GrayLog requested
yum install java-1.8.0-openjdk-headless.x86_64 pwgen -y

# Vars
# -------------------------------------------------------------------------------------------\
G_CONF="/etc/graylog/server/server.conf"
PWD_SECRET=$(pwgen -N 1 -s 96)
ADMIN_PWD=$(echo -n p@ssw0rd | sha256sum | awk $'{print $1}')
SRV_NAME=$(hostname)
SRV_IP=$(hostname -I | cut -d' ' -f1)

# Install repos
cat > /etc/yum.repos.d/mongodb-org.repo <<_EOF_
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
_EOF_

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
cat > /etc/yum.repos.d/elasticsearch.repo <<_EOF_
[elasticsearch-6.x]
name=Elasticsearch repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/oss-6.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
_EOF_

rpm -Uvh https://packages.graylog2.org/repo/packages/graylog-3.1-repository_latest.rpm

# Install servers software
yum install mongodb-org elasticsearch-oss graylog-server -y

echo "cluster.name: graylog" >> /etc/elasticsearch/elasticsearch.yml

systemctl daemon-reload && systemctl enable mongod.service && systemctl start mongod.service
systemctl enable elasticsearch.service && systemctl start elasticsearch.service

echo -e "\n# Custom settings\npassword_secret = $PWD_SECRET"  >> /etc/graylog/server/server.conf
echo "root_password_sha2 = $ADMIN_PWD" >> /etc/graylog/server/server.conf

cat >> /etc/graylog/server/server.conf <<_EOF_
# additional configs
http_bind_address = ${SRV_IP}:9000
root_email = root@localhost
root_timezone = UTC
#
elasticsearch_max_docs_per_index = 20000000
elasticsearch_max_number_of_indices = 20
elasticsearch_shards = 1
elasticsearch_replicas = 0
_EOF_

firewall-cmd --permanent --add-port=9000/tcp
firewall-cmd --reload

echo "http://$SRV_IP:9000"