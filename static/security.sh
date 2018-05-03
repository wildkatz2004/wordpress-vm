#!/bin/bash

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Based on: http://www.techrepublic.com/blog/smb-technologist/secure-your-apache-server-from-ddos-slowloris-and-dns-injection-attacks/

# Protect against DDOS
apt update -q4 & spinner_loading
apt -y install libapache2-mod-evasive
mkdir /var/log/mod_evasive
chown -R www-data: /var/log/mod_evasive

if [ -f $ENVASIVE ]; then
     rm  $ENVASIVE
	  
cat > "$ENVASIVE" << EOF 
<IfModule mod_evasive20.c>
	DOSPageCount        5
	DOSSiteCount        50
	DOSPageInterval     1
	DOSSiteInterval     1
	DOSBlockingPeriod   600
	DOSLogDir           "/var/log/mod_evasive"
</IfModule>
EOF
fi

sudo systemctl restart apache2.service
# Protect against Slowloris
#apt -y install libapache2-mod-qos
a2enmod reqtimeout # http://httpd.apache.org/docs/2.4/mod/mod_reqtimeout.html

# Protect against DNS Injection
apt -y install libapache2-mod-spamhaus
if [ ! -f $SPAMHAUS ]
then
    touch $SPAMHAUS
    cat << SPAMHAUS >> "$APACHE2"
# Spamhaus module
<IfModule mod_spamhaus.c>
  MS_METHODS POST,PUT,OPTIONS,CONNECT
  MS_WhiteList /etc/spamhaus.wl
  MS_CacheSize 256
</IfModule>
SPAMHAUS
fi

if [ -f $SPAMHAUS ]
then
    echo "Adding Whitelist IP-ranges..."
    cat << SPAMHAUSconf >> "$SPAMHAUS"
# Whitelisted IP-ranges
192.168.0.0/16
172.16.0.0/12
10.0.0.0/8
SPAMHAUSconf
else
    echo "No file exists, so not adding anything to whitelist"
fi

# Enable $SPAMHAUS
sed -i "s|#MS_WhiteList /etc/spamhaus.wl|MS_WhiteList $SPAMHAUS|g" /etc/apache2/mods-enabled/spamhaus.conf

check_command service apache2 restart
echo "Security added!"
sleep 3
