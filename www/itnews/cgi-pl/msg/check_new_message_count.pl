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
# Program: /www/itnews/cgi-pl/msg/check_new_message_count.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-02      DW              Check unread message count for all message 
#                                               groups to specified user. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use POSIX;
use JSON;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $user_id = paramAntiXSS('user_id') + 0;                 # User ID of message receiver.

my $dbh = dbconnect($COOKIE_MSG);                          

my @msg_unread_cnt = ();
my $js_data = '';

if (sessionAlive($COOKIE_MSG, 1)) {                        # Defined on sm_user.pl, please also note that pulling old messages is an user initiative action, so it should extend the session period.
  @msg_unread_cnt = getMessageGroup($dbh, $user_id);       # Defined on sm_msglib.pl
  
  #-- Note: Since data stored on database has already encoded in UTF-8, and 'encode_json' is by default encoded data with UTF-8. --#
  #--       Therefore, it causes the retrieved data double encoded by UTF-8, and make it to become garbage. So, use latin1       --#
  #--       encoding method as below command, and don't use UTF-8 encoding method to convert data into JSON string format.       --#
  #--       For more information, please see the URL below:                                                                      --#
  #--       https://stackoverflow.com/questions/33802155/perl-json-encode-in-utf-8-strange-behaviour                             --#
  $js_data = JSON->new->latin1->encode(\@msg_unread_cnt);
}
else {
  $js_data = '[]';
}
  
$js_data =~ s/null/""/g;

print header(-type => 'text/html', -charset => 'utf-8');
print $js_data;

dbclose($dbh);
#-- End Main Section --#

