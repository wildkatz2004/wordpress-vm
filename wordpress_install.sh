#!/bin/bash

# Tech and Me, ©2016 - www.techandme.se

# OS Version
OS=$(grep -ic "Ubuntu" /etc/issue.net)
# Passwords
SHUF=$(shuf -i 15-20 -n 1)
MYSQL_PASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
PW_FILE=/var/mysql_password.txt
# Wordpress user and pass
WPDBNAME=worpdress_by_www_techandme_se
WPDBUSER=wordpress_user
WPDBPASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
WPADMINUSER=change_this_user#
WPADMINPASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
# Directories
SCRIPTS=/var/scripts
HTML=/var/www/html
WPATH=$HTML/wordpress
# Apache Vhosts
SSL_CONF="/etc/apache2/sites-available/wordpress_port_443.conf"
HTTP_CONF="/etc/apache2/sites-available/wordpress_port_80.conf"
# Network
IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
# Repos
GITHUB_REPO="https://raw.githubusercontent.com/enoch85/wordpress-vm/master"
STATIC="https://raw.githubusercontent.com/enoch85/wordpress-vm/master/static"
# Commands
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e `uname -r | cut -f1,2 -d"-"` | grep -e [0-9] | xargs sudo apt -y purge)
# Create user for installing if not existing
UNIXUSER=wordpress
UNIXPASS=wordpress


# Check if root
        if [ "$(whoami)" != "root" ]; then
        echo
        echo -e "\e[31mSorry, you are not root.\n\e[0mYou must type: \e[36msudo \e[0mbash $SCRIPTS/wordpress_install.sh"
        echo
        exit 1
fi

# Check Ubuntu version
echo "Checking server OS and version..."
if [ $OS -eq 1 ]
then
        sleep 1
else
        echo "Ubuntu Server is required to run this script."
        echo "Please install that distro and try again."
        exit 1
fi

DISTRO=$(lsb_release -sd | cut -d ' ' -f 2)
version(){
    local h t v

    [[ $2 = "$1" || $2 = "$3" ]] && return 0

    v=$(printf '%s\n' "$@" | sort -V)
    h=$(head -n1 <<<"$v")
    t=$(tail -n1 <<<"$v")

    [[ $2 != "$h" && $2 != "$t" ]]
}

if ! version 16.04 "$DISTRO" 16.04.4; then
    echo "Ubuntu version $DISTRO must be between 16.04 - 16.04.4"
    exit
fi

# Check if it's a clean server
echo "Checking if it's a clean server..."
if [ $(dpkg-query -W -f='${Status}' mysql-common 2>/dev/null | grep -c "ok installed") -eq 1 ];
then
        echo "MySQL is installed, it must be a clean server."
        exit 1
fi

if [ $(dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -c "ok installed") -eq 1 ];
then
        echo "Apache2 is installed, it must be a clean server."
        exit 1
fi

if [ $(dpkg-query -W -f='${Status}' php 2>/dev/null | grep -c "ok installed") -eq 1 ];
then
        echo "PHP is installed, it must be a clean server."
        exit 1
fi

# Create $UNIXUSER if not existing
if id "$UNIXUSER" >/dev/null 2>&1
then
        echo "$UNIXUSER already exists!"
else
        adduser --disabled-password --gecos "" $UNIXUSER
        echo -e "$UNIXUSER:$UNIXPASS" | chpasswd
        usermod -aG sudo $UNIXUSER
fi

if [ -d /home/$UNIXUSER ];
then
        echo "$UNIXUSER OK!"
else
        echo "Something went wrong when creating the user... Script will exit."
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
apt update -q2

# Install aptitude
apt install aptitude -y

# Install packages for Webmin
apt install -y zip perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python

# Install Webmin
sed -i '$a deb http://download.webmin.com/download/repository sarge contrib' /etc/apt/sources.list
wget -q http://www.webmin.com/jcameron-key.asc -O- | sudo apt-key add -
apt update -q2
apt install webmin -y

# Install perl
apt install perl -y

# Set locales
apt install language-pack-en-base -y
sudo locale-gen "sv_SE.UTF-8" && sudo dpkg-reconfigure --frontend=noninteractive locales

# Write MySQL pass to file and keep it safe
echo "MySQL root password: $MYSQL_PASS" > $PW_FILE
chmod 600 $PW_FILE
chown root:root $PW_FILE

# Install MYSQL 5.7
apt install software-properties-common -y
echo "mysql-server-5.7 mysql-server/root_password password $MYSQL_PASS" | debconf-set-selections
echo "mysql-server-5.7 mysql-server/root_password_again password $MYSQL_PASS" | debconf-set-selections
apt install mysql-server-5.7 -y

# mysql_secure_installation
apt -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root:\"
send \"$MYSQL_PASS\r\"
expect \"Would you like to setup VALIDATE PASSWORD plugin?\"
send \"n\r\"
expect \"Change the password for root ?\"
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
apt -y purge expect

# Install Apache
apt install apache2 -y
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
apt install -y \
        php \
	libapache2-mod-php \
	php-mcrypt \
	php-pear \
	php-mbstring \
	php-mysql \
	php-zip

# Download wp-cli.phar to be able to install Wordpress
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Create dir
mkdir $WPATH

# Create wp-cli.yml
touch $WPATH/wp-cli.yml
cat << YML_CREATE > "$WPATH/wp-cli.yml"
apache_modules:
  - mod_rewrite
YML_CREATE

# Show info about wp-cli
wp --info --allow-root

# Download Wordpress
cd $WPATH
wp core download --allow-root --force --debug --path=$WPATH

# Populate DB
mysql -uroot -p$MYSQL_PASS <<MYSQL_SCRIPT
CREATE DATABASE $WPDBNAME;
CREATE USER '$WPDBUSER'@'localhost' IDENTIFIED BY '$WPDBPASS';
GRANT ALL PRIVILEGES ON $WPDBNAME.* TO '$WPDBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
wp core config --allow-root --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass=$WPDBPASS --dbhost=localhost --extra-php <<PHP
define( 'WP_DEBUG', false );
define( 'WP_CACHE_KEY_SALT', 'wpredis_' );
define( 'WP_REDIS_MAXTTL', 9600);
define( 'WP_REDIS_SCHEME', 'unix' );
define( 'WP_REDIS_PATH', '/var/run/redis/redis.sock' );
define( 'WP_AUTO_UPDATE_CORE', true );
PHP
echo "Wordpress DB: $WPDBPASS" >> $PW_FILE

# Install Wordpress
wp core install --allow-root --url=http://$ADDRESS/wordpress/ --title=Wordpress --admin_user=$WPADMINUSER --admin_password=$WPADMINPASS --admin_email=no-reply@techandme.se --skip-email
echo "WP PASS: $WPADMINPASS" > /var/adminpass.txt
chown wordpress:wordpress /var/adminpass.txt

wp core version --allow-root
sleep 3

# Install Apps
wp plugin install --allow-root twitter-tweets --activate
wp plugin install --allow-root social-pug --activate
wp plugin install --allow-root wp-mail-smtp --activate
wp plugin install --allow-root captcha --activate
wp plugin install --allow-root redis-cache --activate

# set pretty urls
wp rewrite structure '/%postname%/' --hard --allow-root
wp rewrite flush --hard --allow-root

# delete akismet and hello dolly
wp plugin delete akismet --allow-root
wp plugin delete hello --allow-root

# Secure permissions
wget -q $STATIC/wp-permissions.sh -P $SCRIPTS
bash $SCRIPTS/wp-permissions.sh

# Hardening security
# create .htaccess to protect uploads directory
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
apt install figlet -y

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
    DocumentRoot $HTML
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
a2ensite wordpress_port_443.conf
a2ensite wordpress_port_80.conf
a2dissite default-ssl
a2dissite 000-default
service apache2 restart

# Get script for Redis
        if [ -f $SCRIPTS/redis-server-ubuntu16.sh ];
                then
                echo "redis-server-ubuntu16.sh exists"
                else
        wget -q $STATIC/redis-server-ubuntu16.sh -P $SCRIPTS
fi

# Install Redis
bash $SCRIPTS/redis-server-ubuntu16.sh
rm $SCRIPTS/redis-server-ubuntu16.sh

# Set secure permissions final
bash $SCRIPTS/wp-permissions.sh

# Change roots .bash_profile
        if [ -f $SCRIPTS/change-root-profile.sh ];
                then
                echo "change-root-profile.sh exists"
                else
        wget -q $STATIC/change-root-profile.sh -P $SCRIPTS
fi
# Change wordpress .bash_profile
        if [ -f $SCRIPTS/change-wordpress-profile.sh ];
                then
                echo "change-wordpress-profile.sh  exists"
                else
        wget -q $STATIC/change-wordpress-profile.sh -P $SCRIPTS
fi
# Get startup-script for root
        if [ -f $SCRIPTS/wordpress-startup-script.sh ];
                then
                echo "wordpress-startup-script.sh exists"
                else
        wget -q $GITHUB_REPO/wordpress-startup-script.sh -P $SCRIPTS
fi

# Welcome message after login (change in /home/wordpress/.profile
        if [ -f $SCRIPTS/instruction.sh ];
                then
                echo "instruction.sh exists"
                else
        wget -q $STATIC/instruction.sh -P $SCRIPTS
fi
# Clears command history on every login
        if [ -f $SCRIPTS/history.sh ];
                then
                echo "history.sh exists"
                else
        wget -q $STATIC/history.sh -P $SCRIPTS
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
# Change wordpress profile
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

# Make $SCRIPTS excutable
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Allow wordpress to run theese scripts
chown wordpress:wordpress $SCRIPTS/instruction.sh
chown wordpress:wordpress $SCRIPTS/history.sh

# Upgrade
aptitude full-upgrade -y

# Remove LXD (always shows up as failed during boot)
apt purge lxd -y

#Cleanup
echo "$CLEARBOOT"

# Reboot
reboot

exit 0
