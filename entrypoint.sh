#!/bin/bash
sed -i "s/\$IP/$(hostname -I | awk '{print $1}')/" /usr/share/nginx/html/index.html
nginx -g 'daemon off;'
