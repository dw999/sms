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
# Program: delete_old_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-23      DW              Remove messages which are sent 14 days before
#                                               for common groups and private groups which
#                                               auto-delete message flag is set to 0.
# V1.0.01       2019-01-15      DW              Let old messages removal days becomes a variable
#                                               and store on system setting 'old_msg_delete_days'. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                      # Defined on sm_webenv.pl

my $cookie_name = $COOKIE_MSG;      
my $dbh = dbconnect($cookie_name);

my $cutoff_days = getSysSettingValue($dbh, 'old_msg_delete_days') + 0;   # Defined on sm_webenv.pl
$cutoff_days = ($cutoff_days > 0)? $cutoff_days : 14;                    # If it is not set, let it be 14 days ago.

if ($dbh ne undef) {
  my @msg_groups = getMessageGroupsToBeChecked($dbh);
  
  foreach my $this_group_id (@msg_groups) {
    my @messages = getMessagesShouldBeDeleted($dbh, $this_group_id, $cutoff_days);
    
    foreach my $this_msg_id (@messages) {
      deleteMessage($dbh, $this_group_id, $this_msg_id);               # Defined on sm_msglib.pl       
    }
  }
}
else {
  print "Unable to connect database msgdb. \n";
}
#-- End Main Section --#


sub getMessageGroupsToBeChecked {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT group_id
    FROM msg_group
    WHERE (group_type = 0
      AND msg_auto_delete = 1)
       OR (group_type = 1
      AND msg_auto_delete = 0)  
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my ($this_msg_id) = $sth->fetchrow_array()) {
      push @result, $this_msg_id;
    }
  }
  
  return @result;
}


sub getMessagesShouldBeDeleted {
  my ($dbh, $group_id, $cutoff_days) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT msg_id
    FROM message
    WHERE group_id = ?
      AND DATEDIFF(CURRENT_TIMESTAMP(), send_time) >= ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $cutoff_days)) {
    while (my ($this_msg_id) = $sth->fetchrow_array()) {
      push @result, $this_msg_id;
    }    
  }
  
  return @result;
}

