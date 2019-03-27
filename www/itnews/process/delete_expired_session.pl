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
# Program: delete_expired_session.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-19      DW              Remove expired web session and login token queue records.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                      # Defined on sm_webenv.pl
our $COOKIE_PDA;

my $cookie_name = $COOKIE_MSG;      
my $dbh = dbconnect($cookie_name);

#-- Clear expired sessions on messaging site database --#
if ($dbh ne undef) {
  deleteExpiredWebSession($dbh);
  deleteUsedAndTimeoutLoginToken($dbh);
  dbclose($dbh);
}
else {
  print "Unable to connect database msgdb. \n";
}

#-- Clear expired sessions on decoy site database --#
$cookie_name = $COOKIE_PDA;
$dbh = dbconnect($cookie_name);
if ($dbh) {
  deleteExpiredWebSession($dbh);
  dbclose($dbh);
}
else {
  print "Unable to connect database pdadb. \n";
}
#-- End Main Section --#


sub deleteExpiredWebSession {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM web_session
    WHERE TIMEDIFF(CURRENT_TIMESTAMP(), sess_until) > '00:00:00'
       OR status <> 'A' 
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to clear expired web session records. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub deleteUsedAndTimeoutLoginToken {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  #-- Note: Maximum life span of login token is 10 minutes. Adding 30 seconds to it is just for precaution only. --#
  $sql = <<__SQL;
  DELETE FROM login_token_queue
    WHERE TIMEDIFF(CURRENT_TIMESTAMP(), token_addtime) >= '00:10:30'
       OR status = 'U'
       OR status = 'T'
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to clear used or timeout login token records. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);  
}
