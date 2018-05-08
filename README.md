# Wordpress Azure VM
Forked from the folks at https://www.techandme.se

This repository is designed to install the goodies listed below on an a clean freshly provisioned Azure Unbuntu 16.04 image.

If using an Azure image, you'll need to insure that ports 80 and 443 are open.

- MariaDB 10.2 (Latest Version)
- Apache 2.4
- Latest Wordpress (updates automatically)
- WP-CLI

To run you must be logged in as root.  Once logged in as root, paste all of the following in to terminal and hit Return: 
curl -L -o 'init_lamp_install.sh' https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/init_lamp_install.sh && sudo bash init_lamp_install.sh

***Use at your own risk.***  

***I will not be liable for any issues, problems or errors that may occur to your server(s) and or IT environment at a a result of using the contents of this repository or anything else that resides within my Github code.***
