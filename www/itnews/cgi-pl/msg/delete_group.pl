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

my ($ok, $msg) = deleteMessageGroup($dbh, $group_id);      # Defined on sm_msglib.pl

if ($ok) {
  redirectTo("/cgi-pl/msg/message.pl");
}
else {
  alert($msg);
  back();
}

dbclose($dbh);
#-- End Main Section --#
