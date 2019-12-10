## GrayLog 3 installer

What does this script:
* Install GrayLog (Mongo, Elastic)
* Install Nginx + Self-Signed sertificates + set https port nginx
* Basic configure GrayLog and Elastic for working
* Correct configured GrayLog api nginx prixy
* SELinux configure
* Admin password generator
* While whaiting GrayLog running status and show connection mrssage to user

## Fast run
```bash
yum install git -y && git clone https://github.com/m0zgen/install-graylog3 && cd install-graylog3 && bash install.sh
```

## Official documentation
* Official [installing manual](https://docs.graylog.org/en/3.1/pages/installation.html)
* Nginx [settings for GrayLog](https://docs.graylog.org/en/3.1/pages/configuration/web_interface.html#configuring-webif-nginx)
* Haow you can [collect messages](https://docs.graylog.org/en/3.1/pages/getting_started/collect.html)
* Multi-Node [setup](https://docs.graylog.org/en/3.1/pages/configuration/multinode_setup.html)