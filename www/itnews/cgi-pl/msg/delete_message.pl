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
# Program: /www/itnews/cgi-pl/msg/delete_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-10      DW              Delete message. 
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

my $group_id = paramAntiXSS('group_id') + 0;               # Message group ID
my $msg_id = paramAntiXSS('msg_id') + 0;                   # Message ID

my $dbh = dbconnect($COOKIE_MSG);                          

my %result = ();
my $update_token = '';
my $js_data = '';
my $json = '';

if (sessionAlive($COOKIE_MSG)) {                                 # Defined on sm_user.pl
  #-- Delete message --#
  my ($ok, $msg) = deleteMessage($dbh, $group_id, $msg_id);      # Defined on sm_msglib.pl

  #-- Get the most updated token and return to the sender --#
  $update_token = getMessageUpdateToken($dbh, $group_id);        # Defined on sm_msglib.pl
  %result = ('update_token' => $update_token);

  $js_data = encode_json \%result;
  $json = <<__JSON;
  {"mg_status": $js_data}
__JSON

  $json =~ s/null/""/g;

  print header(-type => 'text/html', -charset => 'utf-8');
  print $json;
}

dbclose($dbh);
