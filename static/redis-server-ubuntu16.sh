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


if ! version 16.04 "$DISTRO" 16.04.4; then
    echo "Ubuntu version $DISTRO must be between 16.04 - 16.04.4"
    exit
fi

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
install_redis()
{
	echo "Installing Redis"

	# Installing build essentials (if missing) and other required tools
	apt-get -y install build-essential tcl

    # Redis: Download and Extract the Source Code
    cd /tmp
    curl -O http://download.redis.io/redis-stable.tar.gz
    tar xzvf redis-stable.tar.gz
    cd redis-stable

    # Build and Install Redis
    make
    make test
    make install

    mkdir /etc/redis
    cp /tmp/redis-stable/redis.conf /etc/redis


	echo "Redis package was downloaded and built successfully"
}

#############################################################################

configure_redis()
{
# Configure the general settings
sed -i "s|# unixsocket /var/run/redis/redis.sock|unixsocket $REDIS_SOCK|g" $REDIS_CONF
sed -i "s|# unixsocketperm 700|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|# requirepass foobared|requirepass $(cat /tmp/redis_pass.txt)|g" $REDIS_CONF
sed -i "s|supervised no|supervised systemd|g" $REDIS_CONF
sed -i "s|daemonize no|daemonize yes|g" $REDIS_CONF
sed -i "s|# maxmemory <bytes>|maxmemory 250mb|g" $REDIS_CONF
sed -i "s|# maxmemory-policy noeviction|maxmemory-policy allkeys-lru|g" $REDIS_CONF
sudo sed -e "s/^daemonize no$/daemonize yes/" -e "s/^# bind 127.0.0.1$/bind 127.0.0.1/" -e "s/^dir \.\//dir \/var\/lib\/redis\//" -e "s/^loglevel verbose$/loglevel notice/" -e "s/^logfile stdout$/logfile \/var\/log\/redis.log/" $REDIS_CONF | sudo tee /etc/redis/redis.conf
}
#############################################################################

start_redis()
{
# Start Redis
sudo systemctl start redis
sudo systemctl status redis
sleep 5
# Enable Redis to Start at Boot
systemctl enable redis
}
#############################################################################

# Get packages to be able to install Redis
apt update -q4 & spinner_loading
sudo apt install -q -y \
    build-essential \
    tcl \
    php-dev \
    php-pear
    
# Step1
tune_memory
tune_network

# Step 2
install_redis

# Step 3
configure_redis

# Create a Redis systemd Unit File
cat << EOF > /etc/systemd/system/redis.service
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

#Use the below command to create a user and user group.
adduser --system --group --no-create-home redis --quiet
#Then, you have to create the directory.
mkdir /var/lib/redis
#The directory is created and now you have to give the ownership of the directory to the newly created user and user group.
chown redis:redis /var/lib/redis
#You have to block the user or group which doesn't have ownership towards the directory.
chmod 770 /var/lib/redis

echo "--------------------------------------------------------------------------------------------"
echo "Installing Predis on Ubuntu 16.04"
echo "Read more: https://github.com/nrk/predis"
echo "Author: Ralf Rottmann | @ralf | http://rottmann.net"
echo "--------------------------------------------------------------------------------------------"
PHP_CONF_DIR="/etc/php/7.0/apache2/conf.d"
echo "Checking prerequisites..."
echo "Git available?"
[ ! -s /usr/bin/git ] && sudo apt-get -q -y install git || echo "Git already installed."
echo "--------------------------------------------------------------------------------------------"
echo "Step 0: Installing a PHP extension for Redis from https://github.com/phpredis/phpredis"
cd
found=$(find / -name "redis.so" 2> /dev/null)
[[ -n $found ]] && {
  echo "Library already installed."
} ||
{
  git clone http://github.com/phpredis/phpredis
	cd phpredis
	found=$(which phpize)
	[[ ! -n $found ]] && {
		echo "Missing phpize. Installing php7.0-dev..."
		sudo apt-get -q -y install php7.0-dev
	}
	phpize
	./configure
	make && make install
	echo "extension=redis.so" > /etc/php/7.0/mods-available/redis.ini
	sudo ln -sf /etc/php/7.0/mods-available/redis.ini /etc/php/7.0/apache2/conf.d/20-redis.ini
	sudo ln -sf /etc/php/7.0/mods-available/redis.ini /etc/php/7.0/cli/conf.d/20-redis.ini
	sudo service apache2l restart
	echo "Done installing a PHP extension for Redis!"
}


echo "--------------------------------------------------------------------------------------------"
echo "Step 1: Installing the Minimalistic C client for Redis >= 1.2 from https://github.com/redis/hiredis"
cd
found=$(find / -name "libhiredis.so" 2> /dev/null)
[[ -n $found ]] && {
  echo "Library already installed."
} ||
{
  git clone http://github.com/redis/hiredis
	cd hiredis
	make &&	make install
	ldconfig	
	echo "Done."
}

echo "Finished."


# Redis performance tweaks
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

redis-cli SHUTDOWN
rm -f /tmp/redis_pass.txt

echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

# Start Redis
start_redis

# Clean
rm -rf /tmp/redis-stable
rm /tmp/redis-stable.tar.gz

# Cleanup
apt purge -y \
    git \
    build-essential*

apt update -q4 & spinner_loading
apt autoremove -y
apt autoclean

exit
