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
yum install java-1.8.0-openjdk-headless.x86_64 pwgen yum-utils policycoreutils-python lsof -y

# Vars
# -------------------------------------------------------------------------------------------\
G_CONF="/etc/graylog/server/server.conf"
PWD_SECRET=$(pwgen -N 1 -s 96)
ADMN_LOGIN_PWD=$(pwgen -n 8 -N 1)
ADMIN_PWD=$(echo -n $ADMN_LOGIN_PWD | sha256sum | awk $'{print $1}')
SRV_NAME=$(hostname)
SRV_IP=$(hostname -I | cut -d' ' -f1)

# SE_PORTS=(9000 9200 27017 19200)
function seset() {
	setsebool -P httpd_can_network_connect 1
	semanage port -a -t http_port_t -p tcp 9000
	semanage port -a -t http_port_t -p tcp 9200
	semanage port -a -t mongod_port_t -p tcp 27017
	semanage port -a -t mongod_port_t -p tcp 12900
}

function setfw() {
	firewall-cmd --permanent --add-service=http
	firewall-cmd --permanent --add-service=https
	firewall-cmd --reload
}

function enable() {
	systemctl enable $1 && systemctl start $1
}

# Install repos
cat > /etc/yum.repos.d/nginx.repo << _EOF_
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
_EOF_

cat > /etc/yum.repos.d/mongodb-org.repo <<_EOF_
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
_EOF_

# test curl -X GET http://localhost:9200
# test curl -XGET 'http://localhost:9200/_cluster/health?pretty=true'
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

yum-config-manager --enable nginx-mainline

rpm -Uvh https://packages.graylog2.org/repo/packages/graylog-3.1-repository_latest.rpm

# Install servers software
yum install mongodb-org elasticsearch-oss graylog-server nginx -y

echo "cluster.name: graylog" >> /etc/elasticsearch/elasticsearch.yml

seset

systemctl daemon-reload

enable mongod.service
enable elasticsearch.service

echo -e "\n# Custom settings\npassword_secret = $PWD_SECRET"  >> /etc/graylog/server/server.conf
echo "root_password_sha2 = $ADMIN_PWD" >> /etc/graylog/server/server.conf

cat >> /etc/graylog/server/server.conf <<_EOF_
# additional configs
http_bind_address = 127.0.0.1:9000
root_email = root@localhost
root_timezone = UTC
#
elasticsearch_max_docs_per_index = 20000000
elasticsearch_max_number_of_indices = 20
elasticsearch_shards = 1
elasticsearch_replicas = 0
# apis
rest_listen_uri = http://127.0.0.1:9000/graylog/api/
web_listen_uri = http://127.0.0.1:9000/graylog
_EOF_

enable graylog-server

# Setup nginx
mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/gl.conf

cat > /etc/nginx/conf.d/gl.conf << _EOF_
server
{
    listen 80 default_server;
    listen [::]:80 default_server ipv6only=on;
    server_name ${SRV_IP};

    location / {
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Server \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Graylog-Server-URL http://\$server_name/;
      proxy_pass       http://127.0.0.1:9000;
    }
    return 301 https://\$host\$request_uri;
}

server
{
    listen      443 ssl http2;
    server_name ${SRV_IP};

    #ssl
    ssl_certificate /etc/nginx/ssl/self-request.csr;
    ssl_certificate_key /etc/nginx/ssl/self-key.pem;

    ssl_ciphers EECDH:+AES256:-3DES:RSA+AES:RSA+3DES:!NULL:!RC4:!RSA+3DES;
    ssl_prefer_server_ciphers on;

    ssl_protocols  TLSv1.1 TLSv1.2;
    add_header Strict-Transport-Security "max-age=31536000; includeSubdomains; preload";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options nosniff;


    location /
    {
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Server \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Graylog-Server-URL https://\$server_name/;
      proxy_pass       http://127.0.0.1:9000;
    }

    location /graylog/
    {
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Server \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Graylog-Server-URL http://\$server_name/graylog/;
      rewrite          ^/graylog/(.*)\$  /\$1  break;
      proxy_pass       http://127.0.0.1:9000;
    }

}
_EOF_

git clone https://github.com/m0zgen/self-cert-gen
bash self-cert-gen/sgen-conf.sh
mkdir /etc/nginx/ssl
cp self-cert-gen/self-request.csr self-cert-gen/self-key.pem /etc/nginx/ssl/

enable nginx

setfw

# while wait running GrayLog server
secs=$((5 * 60))
while [ $secs -gt 0 ]; do

if lsof -Pi :9000 -sTCP:LISTEN -t >/dev/null ; then
	secs=0
	echo "GrayLog is running!"

	echo "Please login to server after several minutes!"
	echo "Server address: https://$SRV_IP"
	echo "User: admin, pass: $ADMN_LOGIN_PWD"
	echo "User: admin, pass: $ADMN_LOGIN_PWD" >> $SCRIPT_PATH/config.txt

else
   echo -ne "GrayLog is starting process... Please wait in seconds: $secs\033[0K\r"
   sleep 1
   : $((secs--))

   if (( $secs == 1 )); then
   	  secs=0	
      echo "GrayLog does not started. Please try run it manually."
   fi
fi

done
