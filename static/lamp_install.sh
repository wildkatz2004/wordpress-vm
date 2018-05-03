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

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_install.sh\n" "$SCRIPTS"
    exit 1
fi

#Install MariaDB Function

install_mariadb(){

# Write MySQL pass to file and keep it safe
{
echo "[client]"
echo "password='$MARIADB_PASS'"
} > "$MYCNF"
chmod 0600 $MYCNF
chown root:root $MYCNF

# Install MySQL 5.7
#export DEBIAN_FRONTEND="noninteractive"
#apt install software-properties-common -y
#sudo apt-key adv --keyserver pgp.mit.edu --recv-keys 5072E1F5
#sudo add-apt-repository 'deb http://repo.mysql.com/apt/ubuntu/ trusty mysql-5.7'
#sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MARIADB_PASS"
#sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MARIADB_PASS"
#apt update -q4 & spinner_loading
#check_command apt-get install mysql-server -y

# Install MARIADB
apt install software-properties-common -y
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
sudo add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://ftp.ddg.lth.se/mariadb/repo/10.2/ubuntu xenial main'
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password password $MARIADB_PASS"
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password_again password $MARIADB_PASS"
apt update -q4 & spinner_loading
check_command apt install mariadb-server-10.2 -y

# Prepare for Wordpress installation
# https://blog.v-gar.de/2017/02/en-solved-error-1698-28000-in-mysqlmariadb/
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET plugin='' WHERE user='root';"
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET password=PASSWORD('$MARIADB_PASS') WHERE user='root';"
mysql -u root -p"$MARIADB_PASS" -e "flush privileges;"

# mysql_secure_installation
apt -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MARIADB_PASS\r\"
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
apt -y purge expect

# Write a new MariaDB config
run_static_script new_etc_mycnf
}

# Install Apache Function
install_apache_depends(){

    #Install Apache dependencies
    log "Info" "Starting to install dependencies packages for Apache..."
    local apt_list=(openssl libssl-dev libxml2-dev lynx lua-expat-dev libjansson-dev)
    local yum_list=(zlib-devel openssl-devel libxml2-devel lynx expat-devel lua-devel lua jansson-devel)
    if check_sys packageManager apt; then
        for depend in ${apt_list[@]}; do
            error_detect_depends "apt-get -y install ${depend}"
        done
    elif check_sys packageManager yum; then
        for depend in ${yum_list[@]}; do
            error_detect_depends "yum -y install ${depend}"
        done
    fi
    log "Info" "Install dependencies packages for Apache completed..."
}


install_apache(){

    #Install Apache
    check_command apt install apache2 -y

    #Enable Apache Modules
    a2enmod rewrite \
            headers \
            env \
            dir \
            mime \
            ssl \
            setenvif 
}


# Install PHP Dependencies Function
install_php_depends(){

    if check_sys packageManager apt; then
        apt_depends=(
            autoconf patch m4 bison libbz2-dev libgmp-dev libicu-dev libldb-dev libpam0g-dev
            libldap-2.4-2 libldap2-dev libsasl2-dev libsasl2-modules-ldap libc-client2007e-dev libkrb5-dev
            autoconf2.13 pkg-config libxslt1-dev zlib1g-dev libpcre3-dev libtool unixodbc-dev libtidy-dev
            libjpeg-dev libpng-dev libfreetype6-dev libpspell-dev libmhash-dev libenchant-dev libmcrypt-dev
            libcurl4-gnutls-dev libwebp-dev libxpm-dev libvpx-dev libreadline-dev snmp libsnmp-dev
        )
        log "Info" "Starting to install dependencies packages for PHP..."
        for depend in ${apt_depends[@]}
        do
            error_detect_depends "apt-get -y install ${depend}"
        done
        log "Info" "Install dependencies packages for PHP completed..."
     fi
	
}

# Install PHP Function
install_php(){

    if check_sys packageManager apt; then
        apt_php_package=(
		php php7.0-fpm php7.0-common php7.0-mbstring php7.0-xmlrpc php7.0-gd php7.0-xml 
		php7.0-mysql php7.0-cli php7.0-zip php7.0-curl libapache2-mod-php libapache2-mod-fastcgi
        )
        log "Info" "Starting to install primary packages for PHP..."
        for depend in ${apt_php_package[@]}
        do
            error_detect_depends "apt-get -y install ${depend}"
        done
        log "Info" "Install dependencies packages for PHP completed..."
     fi
}

#create mysql cnf
create_php_fpm_conf(){

cat > /etc/apache2/conf-available/php7.0-fpm.conf << EOF 
    <IfModule mod_fastcgi.c>
      AddHandler php.fcgi .php
      Action php.fcgi /php.fcgi
      Alias /php.fcgi /usr/lib/cgi-bin/php.fcgi
      FastCgiExternalServer /usr/lib/cgi-bin/php.fcgi -socket /run/php/php7.0-fpm.sock -pass-header Authorization -idle-timeout 3600
      <Directory /usr/lib/cgi-bin>
        Require all granted
      </Directory>
    </IfModule>
EOF

    log "Info" "create php7.0-fpm.conf file at /etc/apache2/conf-available/php7.0-fpm.conf completed."

}

# Configure PHP Function
configure_php(){
    
    # Configure PHP
    sed -i "s|allow_url_fopen =.*|allow_url_fopen = On|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|max_execution_time =.*|max_execution_time = 360|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|file_uploads =.*|file_uploads = On|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|upload_max_filesize =.*|upload_max_filesize = 100M|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|memory_limit =.*|memory_limit = 256M|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|post_max_size =.*|post_max_size = 110M|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|cgi.fix_pathinfo =.*|cgi.fix_pathinfo=0|g" /etc/php/7.0/fpm/php.ini
    sed -i "s|date.timezone =.*|date.timezone = US/Central|g" /etc/php/7.0/fpm/php.ini

    if [ -f  /etc/apache2/conf-available/php7.0-fpm.conf ]; then
          rm /etc/apache2/conf-available/php7.0-fpm.conf
    fi

    create_php_fpm_conf

    #enable /etc/apache2/conf-available/php-fpm.confcat
    sudo a2enconf php7.0-fpm
    # Next, enable the following Apache modules...
    sudo a2dismod php mpm_prefork
    sudo a2enmod actions fastcgi alias mpm_worker 
    # And disable this module, which is mod_php:
    sudo a2dismod php7.0
    # Restart Apache
    sudo service apache2 restart && sudo service php7.0-fpm restart

}

# Install Lamp
lamp(){

  install_mariadb
  #install_apache_depends
  install_apache
  #install_php_depends
  install_php
  configure_php

}

lamp 
