#!/bin/bash

# Tech and Me, ©2016 - www.techandme.se

SHUF=$(shuf -i 20-25 -n 1)
MYSQL_PASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
PW_FILE=/var/mysql_password.txt
WPDBNAME=worpdress_by_www_techandme_se
WPDBUSER=wordpress_user
WPDBPASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
SCRIPTS=/var/scripts
HTML=/var/www/html
WPATH=$HTML/wordpress
SSL_CONF="/etc/apache2/sites-available/wordpress_port_443.conf"
HTTP_CONF="/etc/apache2/sites-available/wordpress_port_80.conf"
IFCONFIG="/sbin/ifconfig"
IFACE=$($IFCONFIG | grep HWaddr | cut -d " " -f 1)
ADDRESS=$($IFCONFIG | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e `uname -r | cut -f1,2 -d"-"` | grep -e [0-9] | xargs sudo apt-get -y purge)
GITHUB_REPO=https://raw.githubusercontent.com/enoch85/wordpress-vm/master/

# Check if root
        if [ "$(whoami)" != "root" ]; then
        echo
        echo -e "\e[31mSorry, you are not root.\n\e[0mYou must type: \e[36msudo \e[0mbash $SCRIPTS/wordpress_install.sh"
        echo
        exit 1
fi

# Create $SCRIPTS dir
      	if [ -d $SCRIPTS ]; then
      		sleep 1
      		else
      	mkdir $SCRIPTS
fi

# Change DNS
echo "nameserver 8.26.56.26" > /etc/resolvconf/resolv.conf.d/base
echo "nameserver 8.20.247.20" >> /etc/resolvconf/resolv.conf.d/base

# Check network
sudo ifdown $IFACE && sudo ifup $IFACE
nslookup google.com
if [[ $? > 0 ]]
then
    echo "Network NOT OK. You must have a working Network connection to run this script."
    exit
else
    echo "Network OK."
fi

# Update system
apt-get update

# Install perl
apt-get install perl -y

# Set locales
sudo locale-gen "sv_SE.UTF-8" && sudo dpkg-reconfigure locales

# Show MySQL pass, and write it to a file in case the user fails to write it down
echo
echo -e "Your MySQL root password is: \e[32m$MYSQL_PASS\e[0m"
echo "Please save this somewhere safe. The password is also saved in this file: $PW_FILE."
echo "Root DB: $MYSQL_PASS" > $PW_FILE
chmod 600 $PW_FILE
echo -e "\e[32m"
read -p "Press any key to continue..." -n1 -s
echo -e "\e[0m"

# Install MYSQL 5.6
apt-get install software-properties-common -y
echo "mysql-server-5.6 mysql-server/root_password password $MYSQL_PASS" | debconf-set-selections
echo "mysql-server-5.6 mysql-server/root_password_again password $MYSQL_PASS" | debconf-set-selections
apt-get install mysql-server-5.6 -y

# mysql_secure_installation
aptitude -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MYSQL_PASS\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"
aptitude -y purge expect

# Install Apache
apt-get install apache2 -y
a2enmod rewrite \
        headers \
        env \
        dir \
        mime \
        ssl \
        setenvif

# Set hostname and ServerName
sudo sh -c "echo 'ServerName wordpress' >> /etc/apache2/apache2.conf"
sudo hostnamectl set-hostname wordpress
service apache2 restart

# Install PHP 7.0
apt-get install python-software-properties -y && echo -ne '\n' | sudo add-apt-repository ppa:ondrej/php
apt-get update
apt-get install -y \
        libapache2-mod-php7.0 \
        php7.0-common \
        php7.0-mysql \
        php7.0-intl \
        php7.0-mcrypt \
        php7.0-ldap \
        php7.0-imap \
        php7.0-cli \
        php7.0-gd \
        php7.0-json \
        php7.0-curl \
	php7.0-xml \
	php7.0-zip

# Download wp-cli.phar to be able to create database
# and activate apps
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
sudo -u wordpress -i -- wp --info

# Create dir and cd into it...
mkdir $WPATH
cd $WPATH

# Download Wordpress
sudo -u wordpress -i -- wp core download

# Populate DB
mysql -uroot -p$MYSQL_PASS <<MYSQL_SCRIPT
CREATE DATABASE $WPDBNAME;
CREATE USER '$WPDBUSER'@'localhost' IDENTIFIED BY '$WPDBPASS';
GRANT ALL PRIVILEGES ON $WPDBNAME.* TO '$WPDBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
sudo -u wordpress -i -- wp core config --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass=$WPDBPASS --dbhost=localhost
echo "Wordpress DB: $WPDBPASS" >> $PW_FILE

sudo -u wordpress -i -- wp core version
sleep 3

# Install Apps
sudo -u wordpress -i -- wp plugin install twitter-tweets --activate
sudo -u wordpress -i -- wp plugin install social-pug --activate
sudo -u wordpress -i -- wp plugin install wp-mail-smtp --activate

# set pretty urls
sudo -u wordpress -i -- wp rewrite structure '/%postname%/' --hard
sudo -u wordpress -i -- wp rewrite flush --hard

# delete akismet and hello dolly
sudo -u wordpress -i -- wp plugin delete akismet
sudo -u wordpress -i -- wp plugin delete hello

# Secure permissions
wget -q $GITHUB_REPO/wp-permissions.sh -P $SCRIPTS
bash $SCRIPTS/wp-permissions.sh

# Hardening security
#create .htaccess to protect uploads directory
cat > $WPATH/wp-content/uploads/.htaccess <<'EOL'
# Protect this file
<Files .htaccess>
Order Deny,Allow
Deny from All
</Files>
# whitelist file extensions to prevent executables being
# accessed if they get uploaded
order deny,allow
deny from all
<Files ~ ".(docx?|xlsx?|pptx?|txt|pdf|xml|css|jpe?g|png|gif)$">
allow from all
</Files>
EOL

# Change values in php.ini (increase max file size)
# max_execution_time
sed -i "s|max_execution_time = 30|max_execution_time = 3500|g" /etc/php/7.0/apache2/php.ini
# max_input_time
sed -i "s|max_input_time = 60|max_input_time = 3600|g" /etc/php/7.0/apache2/php.ini
# memory_limit
sed -i "s|memory_limit = 128M|memory_limit = 512M|g" /etc/php/7.0/apache2/php.ini
# post_max
sed -i "s|post_max_size = 8M|post_max_size = 1100M|g" /etc/php/7.0/apache2/php.ini
# upload_max
sed -i "s|upload_max_filesize = 2M|upload_max_filesize = 1000M|g" /etc/php/7.0/apache2/php.ini

# Install Figlet
apt-get install figlet -y

# Generate $SSL_CONF
if [ -f $SSL_CONF ];
        then
        echo "Virtual Host exists"
else
        touch "$SSL_CONF"
        cat << SSL_CREATE > "$SSL_CONF"
<VirtualHost *:443>
    Header add Strict-Transport-Security: "max-age=15768000;includeSubdomains"
    SSLEngine on

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $HTML
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>

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
if [ -f $HTTP_CONF ];
        then
        echo "Virtual Host exists"
else
        touch "$HTTP_CONF"
        cat << HTTP_CREATE > "$HTTP_CONF"

<VirtualHost *:80>

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $HTTP
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>

</VirtualHost>
HTTP_CREATE
echo "$HTTP_CONF was successfully created"
sleep 3
fi

# Enable new config
a2ensite $SSL_CONF
a2ensite $HTTP_CONF
a2dissite default-ssl
a2dissite 000-default
service apache2 restart

# Get script for Redis
        if [ -f $SCRIPTS/install-redis-php-7.sh ];
                then
                echo "install-redis-php-7.sh exists"
                else
        wget -q $GITHUB_REPO/install-redis-php-7.sh -P $SCRIPTS
fi

# Install Redis
bash $SCRIPTS/install-redis-php-7.sh
rm $SCRIPTS/install-redis-php-7.sh

# Set secure permissions final
bash $SCRIPTS/wp-permissions.sh

# Change roots .bash_profile
        if [ -f $SCRIPTS/change-root-profile.sh ];
                then
                echo "change-root-profile.sh exists"
                else
        wget -q $GITHUB_REPO/change-root-profile.sh -P $SCRIPTS
fi
# Change wordpress .bash_profile
        if [ -f $SCRIPTS/change-wordpress-profile.sh ];
                then
                echo "change-wordpress-profile.sh  exists"
                else
        wget -q $GITHUB_REPO/change-wordpress-profile.sh -P $SCRIPTS
fi
# Get startup-script for root
        if [ -f $SCRIPTS/wordpress-startup-script.sh ];
                then
                echo "wordpress-startup-script.sh exists"
                else
        wget -q $GITHUB_REPO/wordpress-startup-script.sh -P $SCRIPTS
fi

# Welcome message after login (change in /home/ocadmin/.profile
        if [ -f $SCRIPTS/instruction.sh ];
                then
                echo "instruction.sh exists"
                else
        wget -q $GITHUB_REPO/instruction.sh -P $SCRIPTS
fi
# Clears command history on every login
        if [ -f $SCRIPTS/history.sh ];
                then
                echo "history.sh exists"
                else
        wget -q $GITHUB_REPO/history.sh -P $SCRIPTS
fi

# Change root profile
        	bash $SCRIPTS/change-root-profile.sh
if [[ $? > 0 ]]
then
	echo "change-root-profile.sh were not executed correctly."
	sleep 10
else
	echo "change-root-profile.sh script executed OK."
	rm $SCRIPTS/change-root-profile.sh
	sleep 2
fi
# Change ocadmin profile
        	bash $SCRIPTS/change-wordpress-profile.sh
if [[ $? > 0 ]]
then
	echo "change-wordpress-profile.sh were not executed correctly."
	sleep 10
else
	echo "change-wordpress-profile.sh executed OK."
	rm $SCRIPTS/change-wordpress-profile.sh
	sleep 2
fi

# Allow wordpress to run theese scripts
chown wordpress:wordpress $SCRIPTS/instruction.sh
chown wordpress:wordpress $SCRIPTS/history.sh

# Make $SCRIPTS excutable 
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Upgrade
aptitude full-upgrade -y

#Cleanup
echo "$CLEARBOOT"

# Reboot
reboot

exit 0
