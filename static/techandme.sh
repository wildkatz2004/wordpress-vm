#!/bin/bash
WANIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
ADDRESS=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
WPADMINUSER=$(grep "WP USER:" /var/adminpass.txt)
WPADMINPASS=$(grep "WP PASS:" /var/adminpass.txt)
MYSQLVER=$(mysql --version|awk '{ print $5 }'|awk -F\, '{ print $1 }')
clear
figlet -f small D"&"B Consulting
echo "           http://duanebritting.com/"
echo
# Check php version
 php -i | grep 'PHP Version'
# Check apache version
apachectl -v
# Check mysql version
echo "MySQL Ver: $MYSQLVER"
echo "|NETWORK|"
echo "WAN IP: $WANIP"
echo "LAN IP: $ADDRESS"
echo
echo "|WORDPRESS LOGIN|"
echo "$WPADMINUSER"
echo "$WPADMINPASS"
echo
echo "|MySQL|"
echo "PASS: cat /root/.my.cnf"
echo
exit 0
