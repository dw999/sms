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
# Program: /www/itnews/cgi-pl/msg/check_message_update_token.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-08      DW              Get most updated update token of specified group.
# V1.0.01       2018-08-05      DW              Check also the user current status (on both system 
#                                               and message group level). If user is inactive or
#                                               kicked from the group, inform calling program via
#                                               value of '$update_token' to take appropriated action.
# V1.0.02       2018-08-21      DW              If a given user for a group has unread message, renew
#                                               message update token again. It would resolve an issue
#                                               of new message(s) come in as the user sends out message. 
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
my $user_id = paramAntiXSS('user_id') + 0;                 # User ID

my $dbh = dbconnect($COOKIE_MSG);                          

my %result = ();
my $update_token = '';
my $js_data = '';
my $json = '';

if (sessionAlive($COOKIE_MSG, 0)) {                          # Defined on sm_user.pl
  if (isUserLocked($dbh, $user_id)) {
    $update_token = 'user_locked';
  }
  elsif (isNotGroupMember($dbh, $group_id, $user_id)) {
    $update_token = 'not_group_member';
  }
  else {
    #-- It lets iPhone show abnormal behaviour, so it is fronzen until the problem is cleared. --#
    #if (hasUnreadMessage($dbh, $group_id, $user_id)) {
    #  _updateGroupRefreshToken($dbh, $group_id);             # Defined on sm_msglib.pl
    #}
    
    $update_token = getMessageUpdateToken($dbh, $group_id);  # Defined on sm_msglib.pl  
  }
}
else {
  #-- It will make current message group to reload, in order to let expired session quit immediately. --# 
  $update_token = 'expired';
}

%result = ('update_token' => $update_token);

$js_data = encode_json \%result;
$json = <<__JSON;
{"mg_status": $js_data}
__JSON

$json =~ s/null/""/g;

print header(-type => 'text/html', -charset => 'utf-8');
print $json;

dbclose($dbh);
#-- End Main Section --#


sub isUserLocked {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $status, $result);
  
  $sql = <<__SQL;
  SELECT status
    FROM user_list
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($status) = $sth->fetchrow_array();
    $result = (uc($status) eq 'A')? 0 : 1;
  }
  else {
    #-- If unable to get user status, it is better to assume the user has been locked. --# 
    $result = 1;
  }
  $sth->finish;
  
  return $result;
}


sub isNotGroupMember {
  my ($dbh, $group_id, $user_id) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM group_member
    WHERE group_id = ?
      AND user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $user_id)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 0 : 1;
  }
  else {
    #-- Better assume this user is not group member, if it is unable to verify his/her membership. --#
    $result = 1;
  }
  
  return $result;
}


sub hasUnreadMessage {
  my ($dbh, $group_id, $user_id) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM msg_tx a, message b
    WHERE a.msg_id = b.msg_id
      AND b.group_id = ?
      AND a.receiver_id = ?
      AND a.read_status = 'U'
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $user_id)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 1 : 0;
  }
  else {
    #-- If something is in doubt, let the system check it again. --#
    $result = 1;
  }
  $sth->finish;
  
  return $result;
}
