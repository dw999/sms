#!/bin/bash

###
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###

#=========================================================================================================
# Program: install_sms_ubuntu.sh
#
# Ver         Date            Author          Comment
# =======     ===========     ===========     ==========================================
# V1.0.00     2019-01-12      DW              Install SMS on Ubuntu 18.04.
# V1.0.01     2019-04-27      DW              Fix system log rotation configuration file.
#=========================================================================================================

#-- Don't let screen blank --#
setterm -blank 0

clear

#-- Check currently running operating system and it's version --#
v=`hostnamectl | grep "Ubuntu 18.04" | wc -l`
if [[ "$v" -eq 0 ]]
then
  echo "Currently Running" `hostnamectl | grep "Operating System"`
  echo ""
  echo "This SMS installation program is specified for Ubuntu 18.04 or Debian Linux 9 only, running on other Linux distro is"
  echo "likely to fail."
  echo ""
  read -p "Do you want to continue (Y/N)? " TOGO
  if (test ${TOGO} = 'y' || test ${TOGO} = 'Y')
  then
    echo ""
    echo "OK, it is your call, let's go on."
    echo ""
  else
    exit 1
  fi
fi

#-- Check whether SMS has already been installed. If it is, stop proceed. --#
if [ -d "/www/pdatools" ] || [ -d "/www/itnews" ] || [ -d "/www/perl_lib" ]
then
  echo "It seems that SMS has been installed (at least it has been tried before). Therefore, directory '/www'"
  echo "has already existed. If SMS installation with error and you need to try again, you have to delete '/www'"
  echo "manually and re-run installation script 'install_sms.sh'."
  echo ""
  echo "Note: Re-run installation script in a production SMS server will damage all messages on it."
  echo ""
  read -p "Press enter to exit..." dummy
  exit 1
fi

#-- Define variables --#
export BUILD_PRELOAD=N

#-- Start process --#
echo "Before you start the SMS installation, you must fulfil the following requirements:"
echo ""
echo "1. You must be administrative user. (i.e. You are 'root' or 'root' equivalent user)"
echo "2. You need a fast enough internet connection during installation. (> 1 Mb/s)"
echo "3. You have registered two domain names for the decoy site and messaging site, and they have already been pointed to this server's public IP address."
echo "4. You have an email address for the SMS administrator. (Note: It should not link to your true identity)"
echo "5. You have registered at least one Gmail account for SMS operations. (Note: It MUST be Gmail account)"
echo ""
read -p "If you don't fulfil the above requirements, please press CTRL-C to abort. Otherwise, you may press enter to start the installation..." wait_here

echo ""
echo "=================================================================================="
echo "Step 1: Install required applications"
echo "=================================================================================="
echo "Refresh software repository..."
apt-get update >> /tmp/sms_install.log
echo "Install and configure internet time utilities"
apt-get -y install ntp ntpdate > /tmp/sms_install.log
#-- Ensure ntpd is stopped. Otherwise, the next step will fail. --#
systemctl stop ntp >> /tmp/sms_install.log
ntpdate stdtime.gov.hk >> /tmp/sms_install.log
systemctl enable ntp >> /tmp/sms_install.log
systemctl start ntp >> /tmp/sms_install.log
ntpdate -u -s stdtime.gov.hk 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org 0.asia.pool.ntp.org 0.us.pool.ntp.org
systemctl restart ntp 
hwclock -w
#-- If firewall is not installed, install and configure it now. Otherwise, just configure it. --#
fw=`dpkg -l | grep ufw | wc -l`
if [[ "$fw" -eq 0 ]]
then
  echo "Install Firewall"
  apt-get -y install ufw >> /tmp/sms_install.log
fi  
#-- Now configure firewall --#
echo "Configure firewall"
ufw disable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable
echo "Install unzip"
apt-get -y install unzip >> /tmp/sms_install.log
echo "Install curl"
apt-get -y install curl >> /tmp/sms_install.log
echo "Install MariaDB" 
apt-get -y install mariadb-server mariadb-client >> /tmp/sms_install.log
echo "Install Apache HTTP server"
apt-get -y install apache2 >> /tmp/sms_install.log
echo "Install logrotate"
apt-get -y install logrotate >> /tmp/sms_install.log
echo "Install Perl"
apt-get -y install perl >> /tmp/sms_install.log
echo "Install development tools"
apt-get -y install build-essential >> /tmp/sms_install.log
echo "Install Git version control system"
apt-get -y install git >> /tmp/sms_install.log
echo "Install free DNS certificates auto renew utility"
apt-get -y install software-properties-common >> /tmp/sms_install.log
add-apt-repository -y universe >> /tmp/sms_install.log
add-apt-repository -y ppa:certbot/certbot >> /tmp/sms_install.log
apt-get update >> /tmp/sms_install.log
apt-get -y install python-certbot-apache >> /tmp/sms_install.log

echo ""
echo "----------------------------------------------------------------------------------"
echo "Now, you need to configure CPAN which will be used in next step, please accept ALL default values during setup."
echo "After CPAN setup complete, you will stop on command prompt 'cpan', and you should enter 'quit' to exit and continue the installation process."
read -p "Press enter to start ..." dummy
cpan

#-- Step 2: Install required Perl libraries --#
echo ""
echo "=================================================================================="
echo "Step 2: Install required Perl libraries, it may take more than 15 minutes, please wait..."
echo "=================================================================================="
echo "install libcrypt-cbc-perl"
apt-get -y install libcrypt-cbc-perl >> /tmp/sms_install.log
echo "install libcrypt-eksblowfish-perl"
apt-get -y install libcrypt-eksblowfish-perl >> /tmp/sms_install.log
echo "install libcrypt-rijndael-perl"
apt-get -y install libcrypt-rijndael-perl >> /tmp/sms_install.log
echo "install libpath-class-perl"
apt-get -y install libpath-class-perl >> /tmp/sms_install.log
echo "install libemail-sender-perl"
apt-get -y install libemail-sender-perl >> /tmp/sms_install.log
echo "install libemail-mime-perl"
apt-get -y install libemail-mime-perl >> /tmp/sms_install.log
echo "install libhttp-browserdetect-perl"
apt-get -y install libhttp-browserdetect-perl >> /tmp/sms_install.log
echo "install libjson-perl"
apt-get -y install libjson-perl >> /tmp/sms_install.log
echo "install libjson-maybexs-perl"
apt-get -y install libjson-maybexs-perl >> /tmp/sms_install.log
echo "install liblwp-protocol-https-perl"
apt-get -y install liblwp-protocol-https-perl >> /tmp/sms_install.log
echo "install ImageMagick" 
apt-get -y install imagemagick imagemagick-doc libimage-magick-perl libmagick++-dev >> /tmp/sms_install.log
echo "install libauthen-passphrase-perl"
apt-get -y install libauthen-passphrase-perl >> /tmp/sms_install.log
echo "install perl-www-telegram-botapi"
git clone https://github.com/Robertof/perl-www-telegram-botapi.git >> /tmp/sms_install.log
mkdir -p /usr/share/perl5/WWW/Telegram >> /tmp/sms_install.log 
cp perl-www-telegram-botapi/lib/WWW/Telegram/BotAPI.pm /usr/share/perl5/WWW/Telegram >> /tmp/sms_install.log
rm -rf perl-www-telegram-botapi >> /tmp/sms_install.log
echo "install Email::Sender::Transport::SMTP::TLS"
cpan Email::Sender::Transport::SMTP::TLS >> /tmp/sms_install.log

echo ""
echo "=================================================================================="
echo "Step 3: Get required Javascript libraries, please wait..."
echo "=================================================================================="
echo "Get jQuery"
curl -O https://code.jquery.com/jquery-2.1.4.min.js >> /tmp/sms_install.log
mv jquery-2.1.4.min.js jquery.min.js
echo "Get jQuery Mobile"
curl -O http://jquerymobile.com/resources/download/jquery.mobile-1.4.5.zip >> /tmp/sms_install.log
unzip jquery.mobile-1.4.5.zip -d jqm >> /tmp/sms_install.log
rm -f jquery.mobile-1.4.5.zip >> /tmp/sms_install.log
echo "Get jvavscript cookie"
curl -O https://cdn.jsdelivr.net/npm/js-cookie@2/src/js.cookie.min.js 
echo "Get editable selection input"
git clone https://github.com/indrimuska/jquery-editable-select.git >> /tmp/sms_install.log
echo "Get datetime picker"
git clone https://github.com/nehakadam/DateTimePicker.git >> /tmp/sms_install.log

echo ""
echo "=================================================================================="
echo "Step 4: Copy program files and Javascript libraries to pre-defined directories..."
echo "=================================================================================="
#-- Copy program files and prepare directories access rights --#
mkdir -p /www
cp -Rf ./www/* /www
chmod 777 /www/itnews/data
chmod 777 /www/itnews/data/thumbnail
chmod 777 /www/pdatools/data
chmod 777 /www/pdatools/cgi-pl/tools
chmod 777 /www/pdatools/cgi-pl/tools/*
chmod 777 /www/pdatools/images
chmod 666 /www/pdatools/images/*
#-- Make all Perl scripts executable --# 
find /www/ -type f -iname "*.pl" -exec chmod +x {} \;
#-- Copy required javascript libraries to decoy site --#
cp -f jquery.min.js /www/pdatools/js
cp -f ./jqm/* /www/pdatools/js
mkdir -p /www/pdatools/js/images
cp -Rf ./jqm/images/* /www/pdatools/js/images
cp -Rf ./DateTimePicker/dist/* /www/pdatools/js
#-- Copy required javascript libraries to messaging site --#
cp -f jquery.min.js /www/itnews/js
cp -f ./jqm/* /www/itnews/js
mkdir -p /www/itnews/js/images
cp -Rf ./jqm/images/* /www/itnews/js/images
cp -f js.cookie.min.js /www/itnews/js
cp -f jquery-editable-select/dist/* /www/itnews/js
#-- Clean up javascript libraries installation files --#
rm -rf jqm/*
rmdir jqm
rm -rf DateTimePicker/*
rm -rf DateTimePicker/.git
rm -f DateTimePicker/.gitignore
rmdir DateTimePicker
rm -rf jquery-editable-select/*
rm -rf jquery-editable-select/.git
rm -r jquery-editable-select/.gitignore
rmdir jquery-editable-select
rm -f js.cookie.min.js
rm -f jquery.min.js

echo ""
echo "=================================================================================="
echo "Step 5: Prepare database server and create databases."
echo "=================================================================================="
echo "Now, you need to setup administrative account password for the database server."
echo "Note: The administrative account password of database server is now blank, so you"
echo "      just press enter as you are asked for it in next question. However, you must"
echo "      choose to setup your database server administrative passowrd in this stage."
echo ""
read -p "Press enter to start..." dummy
systemctl enable mariadb.service >> /tmp/sms_install.log
systemctl start mariadb.service >> /tmp/sms_install.log
mysql_secure_installation
echo ""
echo "----------------------------------------------------------------------------------"
echo "After the database server has been configured, I can now install the required databases for you."
echo "You need to input the database administrative password you just created in this stage."
echo ""
read -p "Press enter to start..." dummy
echo ""
mysql --user=root -p < db/create_db.sql

echo ""
echo "=================================================================================="
echo "Step 6. Input essential data to SMS"
echo "=================================================================================="
echo "Note: For more details of SMS connection mode, please refer to SMS user guide."
echo ""
perl input_sms_data.pl

echo ""
echo "=================================================================================="
echo "Step 7: Install SSL certificates to the sites"
echo "=================================================================================="
echo "You need to generate two SSL certificates for the sites, I should find their domain names for you, please input SMS"
echo "administrator email in this step, and select the choice to generate SSL certificates for BOTH sites."
read -p "Press enter to start..." dummy
perl generate_ssl_conf.pl ubuntu18 >> /tmp/sms_install.log
cp -Rf apache24/ubuntu18/httpd_conf/* /etc/apache2
cp -f apache24/ubuntu18/ssl_cert_and_key/cert/* /etc/ssl/certs
cp -f apache24/ubuntu18/ssl_cert_and_key/key/* /etc/ssl/private
rm -f /etc/apache2/sites-available/*.template
rm -f /etc/apache2/sites-enabled/*
#-- Activate Apache modules --#
a2enmod rewrite >> /tmp/sms_install.log
a2enmod cgi >> /tmp/sms_install.log
a2enmod ssl >> /tmp/sms_install.log
a2enmod negotiation >> /tmp/sms_install.log
a2enmod include >> /tmp/sms_install.log
a2enmod alias >> /tmp/sms_install.log
a2enmod headers >> /tmp/sms_install.log
#-- Activate sites --#
a2ensite non-ssl >> /tmp/sms_install.log
a2ensite ssl-decoy-site >> /tmp/sms_install.log
a2ensite ssl-message-site >> /tmp/sms_install.log
systemctl enable apache2 >> /tmp/sms_install.log
systemctl restart apache2 >> /tmp/sms_install.log
#-- Note: 1. Apache must be up and running as execute 'certbot'.                                                             --#
#--       2. SSL certificates getting process often fail in this stage. If it is the case, just login as root and re-run the --#
#--          below command.                                                                                                  --# 
certbot --apache
y=`cat /etc/apache2/sites-available/ssl-decoy-site.conf | grep "letsencrypt" | wc -l`
if [[ "$y" -eq 0 ]]
then
  echo ""
  echo "******************************************************************************"
  echo "SSL certificate generation process is failure, but don't worry, you may re-run"
  echo "the following command after SMS installation to fix this problem:"
  echo ""
  echo "certbot --apache"
  echo "******************************************************************************"
  echo ""
  read -p "Press enter to continue..." dummy
fi  

echo ""
echo "=================================================================================="
echo "Step 8: Configure the Linux system settings"
echo "=================================================================================="
echo "Configure scheduled tasks"
cp -f /etc/crontab /etc/crontab.bkup
cp -f ./sys/ubuntu18/crontab.sms_only /etc/crontab
echo "Configure system log rotation"
cp -f ./sys/ubuntu18/rsyslog /etc/logrotate.d
systemctl restart cron

echo ""
echo "=================================================================================="
echo "Step 9: Build audio file converter FFmpeg (optional)"
echo "=================================================================================="
echo "Audio converter is used to convert commonly used audio input file formats to OGG audio file format, which is"
echo "widely supported as web application audio standard (except iOS)."
echo ""
read -p "Install FFmpeg (Y/N)? " CHOICE
if (test ${CHOICE} = 'y' || test ${CHOICE} = 'Y')
then
  #-- Note: Audio converter setting should be added to SMS automatically, after FFmpeg is built and deployed. --#
  dir=`pwd`;
  cd ./ffmpeg
  chmod +x ./build_ffmpeg.sh
  source ./build_ffmpeg.sh
  cd $dir
else
  perl remove_converter_setting.pl
  echo ""
  echo "You have no audio file converter installed, so SMS will handle audio files as attachments and will not"
  echo "run them directly on web page. You may install it later by using the shell script 'build_ffmpeg.sh' on"
  echo "directory 'ffmpeg' of the installation package."
  echo ""
  read -p "Press enter to continue..." dummy
fi

echo ""
echo "=================================================================================="
echo "Step 10: Install system defender (optional)"
echo "=================================================================================="
echo "System defender is used to provide minimum protection of your SMS server from hackers. It is better to have it, but"
echo "it is not a necessary component to run SMS. If you choose to install system defender, you will be asked to input"
echo "the database administrative password you created in step 5."
echo ""
read -p "Install system defender (Y/N) " choice
if (test ${choice} = 'y' || test ${choice} = 'Y')
then
  echo ""
  mysql --user=root -p < defender/create_defender_db.sql
  mkdir -p /batch
  cp -f ./defender/ubuntu18/*.pl /batch
  chmod +x /batch/*.pl
  cp -f ./sys/ubuntu18/crontab.sms_plus_defender /etc/crontab
  systemctl restart cron
fi  

echo ""
echo "=================================================================================="
echo "Finalize installation"
echo "=================================================================================="
echo "SMS server has been installed. Details of default SMS system administrator is shown below."
echo "Please write it down and change the passwords at once."
echo ""
echo "Username        : smsadmin"
echo "Happy password  : iamhappy"
echo "Unhappy password: iamunhappy"
echo ""
echo "Now, the server is needed to reboot to complete the installation process."
echo ""
read -p "Press the enter to reboot..." dummy
shutdown -r now
