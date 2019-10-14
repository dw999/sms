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
# Program: /www/itnews/cgi-pl/admin/destroy_entire_system.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-17      DW              Destroy entire system in most dangerous situation.
# V1.0.01       2019-02-20      DW              Destroy database of decoy site also.
# V1.0.02       2019-10-12      DW              Function 'isHeSysAdmin' is moved to sm_user.pl
# V1.0.03       2019-10-14      DW              Fix UTF-8 text garbage issue on email content.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use Encode qw(decode encode);
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $COOKIE_PDA;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);
my $dbx = dbconnect($COOKIE_PDA);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $ip_address = allTrim($user_info{'IP_ADDRESS'});

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  #-- Destroy the entire system --#
  eraseEverything();
  redirectTo("https://www.microsoft.com");
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. --#
  if ($user_id > 0) {
    lockUserAcct($dbh, $user_id);
    informSysAdmin($dbh, $user_id, $ip_address);    
  }
  #-- Expel the suspicious user --#
  redirectTo("/cgi-pl/auth/logout.pl");  
}

dbclose($dbh);
dbclose($dbx);
#-- End Main Section --#


sub eraseEverything {
  deleteDatabase($dbh, 'msgdb');
  deleteDatabase($dbx, 'pdadb');
  deleteAllFiles();
}


sub deleteDatabase {
  my ($dbc, $db_name) = @_;
  my ($sql, $sth, @tables);
  
  $sql = <<__SQL;
  SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = ?
    ORDER BY table_name;
__SQL
  
  $sth = $dbc->prepare($sql);
  if ($sth->execute($db_name)) {
    while (my ($this_table) = $sth->fetchrow_array()) {
      push @tables, $this_table;
    }
  }
  $sth->finish;
  
  foreach my $this_table (@tables) {
    $sql = <<__SQL;
    DELETE FROM $this_table
__SQL

    $sth = $dbc->prepare($sql);
    $sth->execute();
    $sth->finish;
  }
  
  foreach my $this_table (@tables) {
    $sql = <<__SQL;
    DROP TABLE $this_table
__SQL

    $sth = $dbc->prepare($sql);
    $sth->execute();
    $sth->finish;
  }  
}


sub deleteAllFiles {
  my ($cmd);

  $cmd = "rm -rf /www/itnews/data/*";
  system($cmd);
  $cmd = "rm -rf /www/itnews/data/thumbnail/*";
  system($cmd);
  $cmd = "rm -rf /www/pdatools/data/*";
  system($cmd);
  $cmd = "rm -rf /www/pdatools/data/thumbnail/*";
  system($cmd);
}


sub lockUserAcct {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth);
  
  $sql = <<__SQL;
  UPDATE user_list
    SET status = 'D'
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id)) {
    my $brief_msg = "Lock user account failure (destroy_entire_system)"; 
    my $detail_msg = "Unable to lock a non-administrative user (user id = $user_id) who try to kill the entire system, please lock this guy manually ASAP.";
    _logSystemError($dbh, $user_id, $detail_msg, $brief_msg);
  }
  $sth->finish;
}


sub informSysAdmin {
  my ($dbh, $user_id, $ip_address) = @_;
  my ($sql, $sth, $user, $username, $alias, $name, $current_datetime, $subject, $content);
  
  $sql = <<__SQL;
  SELECT user_name, user_alias, name, CURRENT_TIMESTAMP() AS now
    FROM user_list
    WHERE user_id = ?   
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($username, $alias, $name, $current_datetime) = $sth->fetchrow_array();
    $username = decode('utf8', $username);
    $alias = decode('utf8', $alias);
    $name = decode('utf8', $name);    
    $user = $username . ((allTrim($alias) ne '')? " (Alias: " . allTrim($alias) . ")" : "") . ((allTrim($name) ne '')? " a.k.a. " . allTrim($name) : "");
  }
  else {
    $user = "id = $user_id";
	  my ($year, $month, $day, $hour, $min, $sec) = (localtime())[5, 4, 3, 2, 1, 0];
    $day = sprintf("%02d", $day);
	  $month = sprintf("%02d", $month++);    
	  $year += 1900;
    $hour = sprintf("%02d", $hour);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    $current_datetime = "$year-$month-$day $hour:$min:$sec";
  }
  $sth->finish;
    
  $subject = "Someone try to kill the system, check for it.";
  $content = "This guy, $user, who is not system administrator but some how get into system destroying function at $current_datetime from this IP address $ip_address. His/Her account has been locked. Try to find out what is going on.";
  _informAdminSystemProblem($dbh, $user, $subject, $content);       # Defined on sm_user.pl
}
