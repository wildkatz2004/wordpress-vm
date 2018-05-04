#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
 . <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Generate $SSL_CONF
if [ ! -f $SSL_CONF ];
        then
        touch $SSL_CONF
        cat << SSL_CREATE > $SSL_CONF
<VirtualHost *:443>
    Header add Strict-Transport-Security: "max-age=15768000;includeSubdomains"
    SSLEngine on

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $WPATH
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>
    <FilesMatch \.php$>
        # 2.4.10+ can proxy to unix socket
         SetHandler "proxy:unix:/run/php/php7.2-fpm.sock|fcgi://localhost"
    </FilesMatch>
    SetEnv HOME $WPATH
    SetEnv HTTP_HOME $WPATH

### LOCATION OF CERT FILES ###
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

#    SSLCertificateFile /etc/ssl/example.com/certificate.crt
#    SSLCertificateKeyFile /etc/ssl/example.com/ssl_example_com_se.key
#    SSLCACertificateFile /etc/ssl/example.com/certificate.ca.crt
#    SSLCertificateChainFile /etc/crt/example_com.ca-bundle

</VirtualHost>
SSL_CREATE
echo "$SSL_CONF was successfully created"
sleep 3
fi

# Generate $HTTP_CONF
if [ ! -f $HTTP_CONF ];
        then
        touch $HTTP_CONF
        cat << HTTP_CREATE > $HTTP_CONF

<VirtualHost *:80>

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $WPATH
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>
    <FilesMatch \.php$>
        # 2.4.10+ can proxy to unix socket
         SetHandler "proxy:unix:/run/php/php7.2-fpm.sock|fcgi://localhost"
    </FilesMatch>

</VirtualHost>
HTTP_CREATE
echo "$HTTP_CONF was successfully created"
sleep 3
fi
