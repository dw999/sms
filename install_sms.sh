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
#=========================================================================================================

#-- Don't let screen blank --#
setterm -blank 0

clear

v=`hostnamectl | grep "CentOS Linux 7" | wc -l`
if [[ "$v" -eq 1 ]]
then
  chmod +x ./install_sms_centos.sh
  source ./install_sms_centos.sh
  exit 0
fi

v=`hostnamectl | grep "Ubuntu 18.04" | wc -l`
if [[ "$v" -eq 1 ]]
then
  chmod +x ./install_sms_ubuntu.sh
  source ./install_sms_ubuntu.sh
  exit 0
fi

v=`hostnamectl | grep "Debian GNU/Linux 9" | wc -l`
if [[ "$v" -eq 1 ]]
then
  chmod +x ./install_sms_debian.sh
  source ./install_sms_debian.sh
  exit 0
fi

echo "You are currently running" `hostnamectl | grep "Operating System"`
echo "Which is not supported by SMS yet."
exit 1

