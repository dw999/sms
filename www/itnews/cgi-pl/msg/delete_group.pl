#!/usr/bin/perl
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

##########################################################################################
# Program: /www/itnews/cgi-pl/msg/delete_group.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-13      DW              Remove entire messaging group.
# V1.0.01       2019-10-12      DW              Fix a security loophole by checking whether current
#                                               user is group administrator or system administrator
#                                               before proceed to message group deletion.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $group_id = paramAntiXSS('group_id') + 0;

my $dbh = dbconnect($COOKIE_MSG);                          # Function 'getGroupMembers' need database connection, so it is put in here.

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

#-- Only group administrator or system administrator can delete a message group --#
if (getGroupRole($dbh, $group_id, $user_id) > 0 || isHeSysAdmin($dbh, $user_id) > 0) {     # getGroupRole is defined on sm_msglib.pl, isHeSysAdmin is defined on sm_user.pl
  my ($ok, $msg) = deleteMessageGroup($dbh, $group_id);    # Defined on sm_msglib.pl

  if ($ok) {
    redirectTo("/cgi-pl/msg/message.pl");
  }
  else {
    alert($msg);
    back();
  }
}
else {
  returnToCaller($group_id);  
}

dbclose($dbh);
#-- End Main Section --#


sub returnToCaller {
  my ($group_id) = @_;
 
  print <<__JS;
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
    var f_m_id = (is_iOS == false)? getLocalStoredItem("m_id") : Cookies.get("m_id");        // Defined on common_lib.js : js.cookie.min.js
    var top_id = (is_iOS == false)? getLocalStoredItem("top_id") : Cookies.get("top_id");
    window.location.href = "/cgi-pl/msg/do_sms.pl?g_id=$group_id&f_m_id=" + f_m_id + "&top_id=" + top_id;
  </script>
__JS
}
