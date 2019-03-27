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
# Program: delete_private_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-18      DW              Remove already read messages for private groups,
#                                               which auto-delete message flag is set to 1.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                      # Defined on sm_webenv.pl

my $cookie_name = $COOKIE_MSG;      
my $dbh = dbconnect($cookie_name);

if ($dbh ne undef) {
  my @private_groups = getPrivateMessageGroups($dbh);
  
  foreach my $rec (@private_groups) {
    my $this_group_id = $rec->{'group_id'} + 0;
    my $this_delete_after_read = $rec->{'delete_after_read'} + 0;
    my @messages = getMessagesShouldBeChecked($dbh, $this_group_id, $this_delete_after_read);
    
    foreach my $this_msg_id (@messages) {
      if (allMembersHaveReadThisMessage($dbh, $this_msg_id)) {
        deleteMessage($dbh, $this_group_id, $this_msg_id);                 # Defined on sm_msglib.pl 
      }
      else {
        #-- The message will disappear for user has read this message --#
        my ($ok, $msg) = deleteReadMembersTxRec($dbh, $this_msg_id, $this_delete_after_read);
        if ($ok) {
          _updateGroupRefreshToken($dbh, $this_group_id);                  # Defined on sm_msglib.pl
        }        
      }
    }
  }

  dbclose($dbh);
}
else {
  print "Unable to connect database msgdb. \n";
}
#-- End Main Section --#


sub getPrivateMessageGroups {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT group_id, delete_after_read
    FROM msg_group
    WHERE group_type = 1
      AND msg_auto_delete = 1  
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'group_id' => $data[0], 'delete_after_read' => $data[1]};
    }
  }
  $sth->finish;
  
  return @result;
}


sub getMessagesShouldBeChecked {
  my ($dbh, $group_id, $delete_after_read) = @_;
  my ($sql, $sth, $time_limit, @result);
  
  $time_limit = "00:" . sprintf("%02d", $delete_after_read) . ":00";
  
  $sql = <<__SQL;
  SELECT DISTINCT a.msg_id 
    FROM message a, msg_tx b
    WHERE a.msg_id = b.msg_id
      AND a.group_id = ?
      AND b.read_status = 'R'
      AND TIMEDIFF(CURRENT_TIMESTAMP(), b.read_time) >= ?
    ORDER BY a.msg_id
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $time_limit)) {
    while (my ($this_msg_id) = $sth->fetchrow_array()) {
      push @result, $this_msg_id;
    }
  }
  $sth->finish;
  
  return @result;
}


sub allMembersHaveReadThisMessage {
  my ($dbh, $msg_id) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM msg_tx
    WHERE msg_id = ?
      AND read_status <> 'R'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($msg_id)) {
    my ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 0 : 1;
  }
  else {
    #-- Just play safe --#
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub deleteReadMembersTxRec {
  my ($dbh, $msg_id, $delete_after_read) = @_;
  my ($ok, $msg, $sql, $sth, $time_limit);
  
  $ok = 1;
  $msg = '';
  $time_limit = "00:" . sprintf("%02d", $delete_after_read) . ":00";
  
  $sql = <<__SQL;
  DELETE FROM msg_tx
    WHERE msg_id = ?
      AND read_status = 'R'
      AND TIMEDIFF(CURRENT_TIMESTAMP(), read_time) >= ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($msg_id, $time_limit)) {
    $msg = "Unable to remove delivery history (message id = $msg_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  else {
    
  }
  
  return ($ok, $msg);
}
