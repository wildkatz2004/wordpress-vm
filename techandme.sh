#!/bin/bash
WANIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
ADDRESS=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
WPADMINPASS=$(grep -Fxq "Wordpress admin login" /var/adminpass.txt)
clear
figlet -f small Tech and Me
echo "           https://www.techandme.se"
echo
echo
echo "|NETWORK|"
echo "WAN IP: $WANIP"
echo "LAN IP: $ADDRESS"
echo
echo "|LOGIN|"
echo "WP USER: change_wordpress_user#"
echo "WP PASS: $WPADMINPASS"
echo "MySQL: /var/mysql_password.txt"

exit 0
