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
# Program: install_sms_cto8_stream.sh
#
# Ver         Date            Author          Comment    
# =======     ===========     ===========     ==========================================
# V1.0.00     2020-12-20      DW              Install SMS on CentOS Stream 8 and use Apache web server.
# V1.0.01     2021-02-09      DW              CertBot installation method has been changed by using snap, so that 
#                                             this SMS installation script is updated accordingly. 
#=========================================================================================================

#-- Don't let screen blank --#
setterm -blank 0

clear

#-- Check currently running operating system and it's version --#
v=`hostnamectl | grep "CentOS Stream 8" | wc -l`
if [[ "$v" -eq 0 ]]
then
  echo "Currently Running" `hostnamectl | grep "Operating System"`
  echo ""
  echo "This SMS installation program is specified for CentOS Stream 8 only, running on other Linux distro is"
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
  echo "It seems that SMS has been installed (at least it has been tried before). Therefore, sub-directories 'pdatools', "
  echo "'itnews' or 'perl_lib' has/have already existed on directory '/www'."
  echo ""
  echo "If SMS installation is failure and you need to try again, you have to delete those sub-directories on '/www'"
  echo "manually and re-run installation script 'install_sms.sh'."
  echo ""
  echo "Note: Re-run installation script in a production SMS server will damage all messages on it."
  echo ""
  read -p "Press enter to exit..."
  exit 1
fi

#-- Check whether SELinux is enforced. If it is, disable it and reboot the server before installation. --#
#-- Note: SELinux makes many normal operations of SMS failure during installation and operation.       --#
x=`cat /etc/selinux/config | grep "SELINUX=enforcing" | wc -l`
if (($x > 0))
then
  echo "It seems that the server setting is needed to be modified for SMS installation"
  read -p "Press enter to modify system setting..."
  cp -f /etc/selinux/config /etc/selinux/config.bkup
  cp -f ./sys/centos7/config /etc/selinux/config
  echo ""
  echo "It is done. You need to reboot the server and run the installation program again."
  read -p "Press enter to reboot the server..."
  shutdown -r now
fi  

#-- Ensure the enterprise packages repository installed --#
er=`dnf list installed epel-release | grep epel-release | wc -l`
if [[ "$er" -eq 0 ]]
then 
  echo "Install enterprise packages repository"
  dnf -y install epel-release >> /tmp/sms_install.log
else 
  echo "Refresh software repository, please wait..."
  dnf -y upgrade >> /tmp/sms_install.log
fi

#-- If snapd doesn't exist, install it now and reboot the system. --#
sn=`dnf list installed snapd | grep snapd | wc -l`
if [[ "$sn" -eq 0 ]]
then
  echo "Install snapd, please wait..."
  dnf -y install snapd >> /tmp/sms_install.log
  systemctl enable --now snapd.socket >> /tmp/sms_install.log
  systemctl start snapd.socket >> /tmp/sms_install.log
  systemctl enable --now snap.seeded.service >> /tmp/sms_install.log
  systemctl start snap.seeded.service >> /tmp/sms_install.log
  ln -s /var/lib/snapd/snap /snap
  echo ""
  echo "Since snapd has just been installed, you need to reboot the server and run the installation program again."
  read -p "Press enter to reboot the server..."
  shutdown -r now  
fi

#-- Define variables --#
export BUILD_PRELOAD=N
export PATH=$PATH:/usr/sbin:/usr/local/sbin

#-- Start process --#
clear
echo "Before you start the SMS installation, you must fulfil the following requirements:"
echo ""
echo "1. You must be administrative user. (i.e. You are 'root' or 'root' equivalent user)"
echo "2. You need a fast enough internet connection during installation. (> 1 Mb/s)"
echo "3. You have registered two domain names for the decoy site and messaging site, and they have already been pointed to this server's public IP address."
echo "4. You have an email address for the SMS administrator. (Note: It should not link to your true identity)"
echo "5. You have registered at least one Gmail account for SMS operations. (Note: It MUST be Gmail account)"
echo ""
read -p "If you don't fulfil the above requirements, please press CTRL-C to abort. Otherwise, you may press enter to start the installation..."

echo ""
echo "=================================================================================="
echo "Step 1: Install required applications"
echo "=================================================================================="
echo "Install and configure internet time utilities"
dnf -y install chrony > /tmp/sms_install.log
systemctl enable chronyd >> /tmp/sms_install.log
systemctl start chronyd >> /tmp/sms_install.log
hwclock -w
#-- If firewall is not installed, install and configure it now. Otherwise, just configure it. --#
fw=`dnf list installed firewalld | grep firewalld | wc -l`
if [[ "$fw" -eq 0 ]]
then
  echo "Install firewall"
  dnf -y install firewalld >> /tmp/sms_install.log
fi
echo "Configure firewall"  
systemctl enable firewalld >> /tmp/sms_install.log
systemctl restart firewalld >> /tmp/sms_install.log
firewall-cmd --zone=public --permanent --add-service=ssh
firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --zone=public --permanent --add-service=https
firewall-cmd --zone=public --permanent --add-icmp-block=echo-request
firewall-cmd --reload
echo "Install curl"
dnf -y install curl.x86_64 >> /tmp/sms_install.log
echo "Install unzip"
dnf -y install unzip.x86_64 >> /tmp/sms_install.log
echo "Install bzip2"
dnf -y install bzip2 >> /tmp/sms_install.log
echo "Install MariaDB"
dnf -y install mariadb-server.x86_64 >> /tmp/sms_install.log
echo "Install Apache HTTP server"
dnf -y install httpd.x86_64 >> /tmp/sms_install.log
echo "Install logrotate"
dnf -y install logrotate >> /tmp/sms_install.log
echo "Refresh snap core"
snap wait system seed.loaded
snap install core
snap refresh core
echo "Install Perl"
dnf -y install perl.x86_64 >> /tmp/sms_install.log
echo "Install development tools"
dnf -y groupinstall "Development Tools" >> /tmp/sms_install.log
echo "Install Git version control system"
dnf -y install git.x86_64 >> /tmp/sms_install.log
echo "Install free DNS certificates auto renew utility"
dnf -y install wget python2-tools python2-devel gcc python2-virtualenv augeas-libs libffi-devel openssl-devel python3-virtualenv >> /tmp/sms_install.log
#-- httpd and mod_ssl should have been installed before, put it here is for precaution only. --#
dnf -y install httpd mod_ssl >> /tmp/sms_install.log
#wget https://dl.eff.org/certbot-auto
#mv certbot-auto /usr/bin/certbot
#chown root /usr/bin/certbot
#chmod 0755 /usr/bin/certbot
snap install --classic certbot >> /tmp/sms_install.log
echo "Install CPAN"
dnf -y install perl-IO-Socket-SSL.noarch >> /tmp/sms_install.log
dnf -y install perl-CPAN.noarch >> /tmp/sms_install.log

echo ""
echo "----------------------------------------------------------------------------------"
echo "Now, you need to configure CPAN which will be used in next step, please accept ALL default values during setup."
echo "After CPAN setup complete, you will stop on command prompt 'cpan', and you should enter 'quit' to exit and continue the installation process."
read -p "Press enter to start ..."
cpan

#-- Step 2: Install required Perl libraries --#
echo ""
echo "=================================================================================="
echo "Step 2: Install required Perl libraries, it may take more than 15 minutes, please wait..."
echo "=================================================================================="
echo "install perl-CGI.noarch"
dnf -y install perl-CGI.noarch >> /tmp/sms_install.log
echo "install perl-DBI.x86_64"
dnf -y install perl-DBI.x86_64 >> /tmp/sms_install.log
echo "install perl-URI.noarch"
dnf -y install perl-URI.noarch >> /tmp/sms_install.log
echo "install perl-Encode.x86_64"
dnf -y install perl-Encode.x86_64 >> /tmp/sms_install.log
echo "install perl-JSON.noarch"
dnf -y install perl-JSON.noarch >> /tmp/sms_install.log
echo "install perl-LWP-Protocol-https.noarch"
dnf -y install perl-LWP-Protocol-https.noarch >> /tmp/sms_install.log
echo "install ImageMagick"
dnf -y install ImageMagick.x86_64 >> /tmp/sms_install.log
dnf -y install ImageMagick-perl.x86_64 >> /tmp/sms_install.log
dnf -y install ImageMagick-doc.x86_64 >> /tmp/sms_install.log
dnf -y install ImageMagick-devel.x86_64 >> /tmp/sms_install.log
dnf -y install ImageMagick-c++.x86_64 >> /tmp/sms_install.log
echo "install Crypt::CBC"
cpan Crypt::CBC >> /tmp/sms_install.log
echo "install Crypt::Eksblowfish"
cpan Crypt::Eksblowfish >> /tmp/sms_install.log
echo "install Crypt::Rijndael"
cpan Crypt::Rijndael >> /tmp/sms_install.log
echo "install Path::Class"
cpan Path::Class >> /tmp/sms_install.log
echo "install Email::Sender"
cpan Email::Sender >> /tmp/sms_install.log
echo "install Email::MIME"
cpan Email::MIME >> /tmp/sms_install.log
echo "install HTTP::BrowserDetect"
cpan HTTP::BrowserDetect >> /tmp/sms_install.log
echo "install JSON::MaybeXS"
cpan JSON::MaybeXS >> /tmp/sms_install.log
echo "install Authen::Passphrase"
cpan Authen::Passphrase >> /tmp/sms_install.log
echo "Install Proc::ProcessTable"
cpan Proc::ProcessTable >> /tmp/sms_install.log
echo "install WWW::Telegram::BotAPI"
cpan WWW::Telegram::BotAPI
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
curl -O https://jquerymobile.com/resources/download/jquery.mobile-1.4.5.zip >> /tmp/sms_install.log
unzip jquery.mobile-1.4.5.zip -d jqm >> /tmp/sms_install.log
rm -f jquery.mobile-1.4.5.zip >> /tmp/sms_install.log
echo "Get jvavscript cookie"
curl -O https://cdn.jsdelivr.net/npm/js-cookie@3.0.1/dist/js.cookie.min.js 
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
mkdir -p /www/itnews/data
mkdir -p /www/itnews/data/thumbnail
mkdir -p /www/pdatools/data
mkdir -p /www/pdatools/data/thumbnail
chmod 777 /www/itnews/data
chmod 777 /www/itnews/data/thumbnail
chmod 777 /www/pdatools/data
chmod 777 /www/pdatools/data/thumbnail
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
read -p "Press enter to start..."
systemctl enable mariadb.service >> /tmp/sms_install.log
systemctl start mariadb.service >> /tmp/sms_install.log
mysql_secure_installation
echo ""
echo "----------------------------------------------------------------------------------"
echo "After the database server has been configured, I can now install the required databases for you."
echo "You need to input the database administrative password you just created in this stage."
echo ""
read -p "Press enter to start..."
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
read -p "Press enter to start..."
# 1. Change 'ServerName' of decoy site and messaging site on ssl.conf
# 2. Copy all Apache configuration files (include a specially crafted welcome.conf), pre-load SSL certificates and private key files to locations defined on ssl.conf
# 3. Run 'certbot --apache' to get new SSL certificate and private key from "Let’s Encrypt"
perl generate_ssl_conf.pl os=centos7 ws=apache >> /tmp/sms_install.log
cp -f apache24/centos7/httpd_conf/conf/*.conf /etc/httpd/conf
cp -f apache24/centos7/httpd_conf/conf.d/*.conf /etc/httpd/conf.d
cp -f apache24/centos7/ssl_cert_and_key/cert/* /etc/pki/tls/certs
cp -f apache24/centos7/ssl_cert_and_key/key/* /etc/pki/tls/private
systemctl enable httpd.service >> /tmp/sms_install.log
systemctl start httpd.service >> /tmp/sms_install.log
#-- Note: 1. Apache must be up and running as execute 'certbot'.                                                             --#
#--       2. SSL certificates getting process often fail in this stage. If it is the case, just login as root and re-run the --#
#--          below command.                                                                                                  --# 
certbot --apache
y=`cat /etc/httpd/conf.d/ssl.conf | grep "letsencrypt" | wc -l`
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
  read -p "Press enter to continue..."
fi  
  
echo ""
echo "=================================================================================="
echo "Step 8: Configure the Linux system settings"
echo "=================================================================================="
echo "Configure scheduled tasks"
cp -f /etc/crontab /etc/crontab.bkup
cp -f ./sys/centos7/crontab.sms_only /etc/crontab
echo "Configure system log rotation"
cp -f ./sys/centos8/syslog /etc/logrotate.d
systemctl restart crond

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
  read -p "Press enter to continue..."
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
  cp -f ./defender/*.pl /batch
  chmod +x /batch/*.pl
  cp -f ./sys/centos7/crontab.sms_plus_defender /etc/crontab
  systemctl restart crond
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
read -p "Press the enter to reboot..."
shutdown -r now



