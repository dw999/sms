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
# Program: install_sms.sh
#
# Ver         Date            Author          Comment
# =======     ===========     ===========     ==========================================
# V1.0.00     2019-04-24      DW              Determine currently running platform and switch to corresponding
#                                             SMS installation script.
# V1.0.01     2019-04-25      DW              Include Debian Linux 9 as SMS supported platform.
# V1.0.02     2019-05-17      DW              Let user select desired web server for SMS installation on CentOS 7.
# V1.0.03     2019-05-21      DW              Let user select desired web server for SMS installation on Debian 9 and Ubuntu 18.04.
# V1.0.04     2019-10-02      DW              Include CentOS Linux 8 as SMS supported platform.
# V1.0.05     2020-07-15      DW              Include Ubuntu 20.04 as SMS supported platform. 
# V1.0.06     2020-12-20      DW              Include CentOS Stream 8 as SMS supported platform.
#=========================================================================================================

#-- Don't let screen blank --#
setterm -blank 0

clear

v=`hostnamectl | grep "CentOS Linux 7" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then  
    chmod +x ./install_sms_centos.sh
    source ./install_sms_centos.sh
  else
    chmod +x ./install_sms_cto_nginx.sh
    source ./install_sms_cto_nginx.sh
  fi  
  exit 0
fi

v=`hostnamectl | grep "CentOS Linux 8" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then  
    chmod +x ./install_sms_centos8.sh
    source ./install_sms_centos8.sh
  else
    chmod +x ./install_sms_cto8_nginx.sh
    source ./install_sms_cto8_nginx.sh
  fi  
  exit 0
fi

v=`hostnamectl | grep "CentOS Stream 8" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then  
    chmod +x ./install_sms_cto8_stream.sh
    source ./install_sms_cto8_stream.sh
  else
    chmod +x ./install_sms_cto8_stream_nginx.sh
    source ./install_sms_cto8_stream_nginx.sh
  fi  
  exit 0
fi

v=`hostnamectl | grep "Ubuntu 18.04" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then
    chmod +x ./install_sms_ubuntu.sh
    source ./install_sms_ubuntu.sh
  else
    chmod +x ./install_sms_ubt_nginx.sh
    source ./install_sms_ubt_nginx.sh
  fi    
  exit 0
fi

v=`hostnamectl | grep "Ubuntu 20.04" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then
    chmod +x ./install_sms_ubuntu_20.sh
    source ./install_sms_ubuntu_20.sh
  else
    chmod +x ./install_sms_ubt_20_nginx.sh
    source ./install_sms_ubt_20_nginx.sh
  fi    
  exit 0
fi

v=`hostnamectl | grep "Debian GNU/Linux 9" | wc -l`
if [[ "$v" -eq 1 ]]
then
  echo "Please select web server for SMS installation:"
  echo ""
  echo "1. Nginx web server"
  echo "2. Apache web server"
  echo ""
  echo "Note: If you don't know how to choose, select Nginx web server."
  echo ""
  read -p "Your choice (1 or 2): " choice
  if (test ${choice} = '2')
  then
    chmod +x ./install_sms_debian.sh
    source ./install_sms_debian.sh
  else  
    chmod +x ./install_sms_dbn_nginx.sh
    source ./install_sms_dbn_nginx.sh
  fi
  exit 0
fi

echo "You are currently running" `hostnamectl | grep "Operating System"`
echo "Which is not supported by SMS yet."
exit 1

