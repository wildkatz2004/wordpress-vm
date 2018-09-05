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

# Must be root
if ! is_root
then
    echo "Must be root to run script, in Ubuntu type: sudo -i"
    exit 1
fi

# Check Ubuntu version
echo "Checking server OS and version..."
if [ "$OS" != 1 ]
then
    echo "Ubuntu Server is required to run this script."
    echo "Please install that distro and try again."
    exit 1
fi


#if ! version 16.04 "$DISTRO" 16.04.4; then
#    echo "Ubuntu version $DISTRO must be between 16.04 - 16.04.4"
#    exit
#fi

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi

#############################################################################
tune_memory()
{
	echo "Tuning the memory configuration"
	
	# Get the supporting utilities
	apt-get -y install hugepages

	# Resolve a "Background save may fail under low memory condition." warning
	sysctl vm.overcommit_memory=1

	# Disable the Transparent Huge Pages (THP) support in the kernel
	sudo hugeadm --thp-never
}

#############################################################################

tune_network()
{
	echo "Tuning the network configuration"
	
>/etc/sysctl.conf cat << EOF 
	# Disable syncookies (syncookies are not RFC compliant and can use too muche resources)
	net.ipv4.tcp_syncookies = 0
	# Basic TCP tuning
	net.ipv4.tcp_keepalive_time = 600
	net.ipv4.tcp_synack_retries = 3
	net.ipv4.tcp_syn_retries = 3
	# RFC1337
	net.ipv4.tcp_rfc1337 = 1
	# Defines the local port range that is used by TCP and UDP to choose the local port
	net.ipv4.ip_local_port_range = 1024 65535
	# Log packets with impossible addresses to kernel log
	net.ipv4.conf.all.log_martians = 1
	# Disable Explicit Congestion Notification in TCP
	net.ipv4.tcp_ecn = 0
	# Enable window scaling as defined in RFC1323
	net.ipv4.tcp_window_scaling = 1
	# Enable timestamps (RFC1323)
	net.ipv4.tcp_timestamps = 1
	# Enable select acknowledgments
	net.ipv4.tcp_sack = 1
	# Enable FACK congestion avoidance and fast restransmission
	net.ipv4.tcp_fack = 1
	# Allows TCP to send "duplicate" SACKs
	net.ipv4.tcp_dsack = 1
	# Controls IP packet forwarding
	net.ipv4.ip_forward = 0
	# No controls source route verification (RFC1812)
	net.ipv4.conf.default.rp_filter = 0
	# Enable fast recycling TIME-WAIT sockets
	net.ipv4.tcp_tw_recycle = 1
	net.ipv4.tcp_max_syn_backlog = 20000
	# How may times to retry before killing TCP connection, closed by our side
	net.ipv4.tcp_orphan_retries = 1
	# How long to keep sockets in the state FIN-WAIT-2 if we were the one closing the socket
	net.ipv4.tcp_fin_timeout = 20
	# Don't cache ssthresh from previous connection
	net.ipv4.tcp_no_metrics_save = 1
	net.ipv4.tcp_moderate_rcvbuf = 1
	# Increase Linux autotuning TCP buffer limits
	net.ipv4.tcp_rmem = 4096 87380 16777216
	net.ipv4.tcp_wmem = 4096 65536 16777216
	# increase TCP max buffer size
	net.core.rmem_max = 16777216
	net.core.wmem_max = 16777216
	net.core.netdev_max_backlog = 2500
	# Increase number of incoming connections
	net.core.somaxconn = 65000
EOF

	# Reload the networking settings
	/sbin/sysctl -p /etc/sysctl.conf
}

#############################################################################
install_redis_dev()
{
#Download Redis package and unpack

mkdir -p /tmp/redis
cd /tmp/redis
wget http://download.redis.io/releases/redis-stable.tar.gz
tar xzf redis-stable.tar.gz
cd redis-stable
#Next step is to compile Redis with make utility and install

sudo make
sudo make install clean
sudo mkdir /etc/redis

#Then copy the configuration file to that directory.
sudo cp /tmp/redis/redis-stable/redis.conf /etc/redis
#Use the below command to create a user and user group.
sudo adduser --system --group --no-create-home redis
#Then, you have to create the directory.
sudo mkdir /var/lib/redis
#The directory is created and now you have to give the ownership of the directory to the newly created user and user group.
sudo chown redis:redis /var/lib/redis
#You have to block the user or group which doesn't have ownership towards the directory.
sudo chmod 770 /var/lib/redis

configure_redis
}

#############################################################################
install_redis()
{

# Install Redis
if ! apt -y install redis-server
then
    echo "Installation failed."
    sleep 3
    exit 1
else
    printf "${Green}\nRedis installation OK!${Color_Off}\n"
fi


configure_redis
}

#############################################################################

configure_redis()
{

## Redis performance tweaks ##
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

# Configure the general settings
# sed -i "s|# unixsocket .*|unixsocket $REDIS_SOCK|g" $REDIS_CONF
# sed -i "s|# unixsocketperm .*|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|^port.*|port 6379|" $REDIS_CONF
sed -i "s|# requirepass .*|requirepass $(cat /tmp/redis_pass.txt)|g" $REDIS_CONF
sed -i 's|# rename-command CONFIG ""|rename-command CONFIG ""|' $REDIS_CONF
sed -i "s|supervised no|supervised systemd|g" $REDIS_CONF
sed -i "s|daemonize no|daemonize yes|g" $REDIS_CONF
sed -i "s|# maxmemory <bytes>|maxmemory 250mb|g" $REDIS_CONF
sed -i "s|# maxmemory-policy noeviction|maxmemory-policy allkeys-lru|g" $REDIS_CONF
sed -i "s|dir ./|dir /var/lib/redis|g" $REDIS_CONF
sed -i "s|save 60 10000|# save 60 10000|g" $REDIS_CONF
sed -i "s|save 300 10|# save 300 10|g" $REDIS_CONF
sed -i "s|save 900 1|# save 900 1|g" $REDIS_CONF

# Create a Redis systemd Unit File
cat << EOF > /etc/systemd/system/redis.service
[Unit]
Description=Redis Server
After=network.target

[Service]
Type=forking
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecReload=/bin/kill -USR2 $MAINPID
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

}
#############################################################################

start_redis()
{
# Start Redis
sudo systemctl start redis
sudo systemctl status redis | cat
sudo systemctl stop redis
sudo systemctl enable redis
sudo systemctl restart redis
}
#############################################################################
install_php7()
{
#InstallPhpRedis for PHP 7
#Download PhpRedis
cd /tmp
wget https://github.com/phpredis/phpredis/archive/master.zip -O phpredis.zip
#Unpack, compile and install PhpRedis

unzip -o /tmp/phpredis.zip && cd /tmp/phpredis-master
phpize && ./configure && make && make install
#Now it is necessary to add compiled extension to php config

#Add PhpRedis extension to PHP 7. Use proper path to your php configs e.g. /etc/php/7.1/ , /etc/php/7.2/
echo 'extension=redis.so' | sudo tee /etc/php/7.2/mods-available/redis.ini
sudo ln -s /etc/php/7.2/mods-available/redis.ini /etc/php/7.2/apache2/conf.d/redis.ini
sudo ln -s /etc/php/7.2/mods-available/redis.ini /etc/php/7.2/fpm/conf.d/redis.ini
sudo ln -s /etc/php/7.2/mods-available/redis.ini /etc/php/7.2/cli/conf.d/redis.ini
}
#############################################################################
# Get packages to be able to install Redis
apt update -q4 & spinner_loading
sudo apt install -q -y \
    build-essential \
    tcl8.6 \
    php-dev \
    php-pear

    
# Step1
tune_memory
tune_network

# Step 2
install_redis_dev
rm -f /tmp/redis_pass.txt

# Step 3
install_php7

# Step 4
# Start Redis 
start_redis

#Start php7
sudo service php7.2-fpm status | cat
sudo service php7.2-fpm restart


# Clean
rm -rf /tmp/*


# Cleanup
apt purge -y \
    git \
    build-essential*

apt update -q4 & spinner_loading
apt autoremove -y
apt autoclean

exit
