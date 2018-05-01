#!/bin/bash

# Tech and Me © - 2017, https://www.techandme.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Based on: http://www.techrepublic.com/blog/smb-technologist/secure-your-apache-server-from-ddos-slowloris-and-dns-injection-attacks/

# Protect against DDOS
apt update -q4 & spinner_loading
apt -y install libapache2-mod-evasive
mkdir -p /var/log/apache2/evasive
chown -R www-data:root /var/log/apache2/evasive
if [ ! -f $ENVASIVE ]
then
    touch $ENVASIVE
    cat << ENVASIVE > "$ENVASIVE"
DOSHashTableSize 2048
DOSPageCount 20  # maximum number of requests for the same page
DOSSiteCount 300  # total number of requests for any object by the same client IP on the same listener
DOSPageInterval 1.0 # interval for the page count threshold
DOSSiteInterval 1.0  # interval for the site count threshold
DOSBlockingPeriod 10.0 # time that a client IP will be blocked for
DOSLogDir
ENVASIVE
fi

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

# Install mod_security
apt-get -y install libxml2 libxml2-dev libxml2-utils libaprutil1 libaprutil1-dev libapache2-modsecurity

check_command systemctl restart apache2
rm -rf /usr/share/modsecurity-crs
apt-get install -y git
git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /usr/share/modsecurity-crs

if [ -f  /usr/share/modsecurity-crs/modsecurity_crs_10_setup.conf ]; then
        cp /usr/share/modsecurity-crs/modsecurity_crs_10_setup.conf /usr/share/modsecurity-crs/backup/modsecurity_crs_10_setup.conf.bak
fi
if [ -f  /usr/share/modsecurity-crs/modsecurity_crs_10_setup.conf.example  ]; then
        cp /usr/share/modsecurity-crs/modsecurity_crs_10_setup.conf.example /usr/share/modsecurity-crs/modsecurity_crs_10_setup.conf
fi
sudo 

sudo ln -s ../modsecurity_crs_10_setup.conf activated_rules/modsecurity_crs_10_setup.conf
for f in `ls base_rules`; do sudo ln -s ../base_rules/$f activated_rules/$f; done

if [ -f /etc/modsecurity/modsecurity.conf-recommended ]; then
       cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
fi


if [ -f  /etc/apache2/mods-enabled/security2.conf ]; then
        rm /etc/apache2/mods-enabled/security2.conf 
fi

cat >> /etc/apache2/mods-enabled/security2.conf  << EOF 
 <IfModule security2_module>
	# Default Debian dir for modsecurity's persistent data
	SecDataDir /var/cache/modsecurity
	# Include all the *.conf files in /etc/modsecurity.
	# Keeping your local configuration in that directory
	# will allow for an easy upgrade of THIS file and
	# make your life easier
        IncludeOptional /etc/modsecurity/*.conf
	IncludeOptional /usr/share/modsecurity-crs/rules/*.conf
        # Include OWASP ModSecurity CRS rules if installed
	IncludeOptional /usr/share/modsecurity-crs/owasp-crs.load
</IfModule>
EOF
check_commanda2enmod headers
check_commanda2enmod security2
check_command systemctl restart apache2
echo "Security added!"
sleep 3

