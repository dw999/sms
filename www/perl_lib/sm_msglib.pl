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
# Program: /www/perl_lib/sm_msglib.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-16      DW              Library functions used for messaging system.
# V1.0.01       2018-08-30      DW              Add thumbnail for uploaded image files.
# V1.0.02       2018-09-13      DW              Let functions 'getGroupMessage' and 'getLastSentMessage'
#                                               use a common data gathering function '_gatherMessage'.
# V1.0.03       2019-03-19      DW              Show audio and video file download link for all platforms, 
#                                               Amended function is '_gatherMessage'.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use URI::Escape;
use Crypt::CBC;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;
our $ITN_TN_PATH;

sub getMessageGroup {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, @data, @buffer, @result);
  
  $user_id += 0;
  @result = @buffer = ();
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT DISTINCT a.group_id, a.group_name, a.group_type, b.group_role
      FROM msg_group a, group_member b
      WHERE a.group_id = b.group_id
        AND b.user_id = ?
      ORDER BY a.group_name  
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id)) {
      while (@data = $sth->fetchrow_array()) {
        push @buffer, {'group_id' => $data[0], 'group_name' => $data[1], 'group_type' => $data[2], 'group_role' => $data[3]};
      }      
    }
    else {
      my $detail_msg = $sth->errstr;
      _logSystemError($dbh, $user_id, $detail_msg, 'Unable to retrieve associated message group(s)');
    }
    $sth->finish;
    
    if (scalar(@buffer) > 0) {
      foreach my $rec (@buffer) {
        my $this_group_id = $rec->{'group_id'};
        my $this_group_name = $rec->{'group_name'};
        my $this_group_type = $rec->{'group_type'};
        my $this_group_role = $rec->{'group_role'};
        my $this_unread_cnt = 0;
        
        $sql = <<__SQL;
        SELECT COUNT(*) AS cnt        
          FROM msg_tx a, message b
          WHERE a.msg_id = b.msg_id
            AND a.read_status = 'U'
            AND b.group_id = ?
            AND a.receiver_id = ?
__SQL
        $sth = $dbh->prepare($sql);
        if ($sth->execute($this_group_id, $user_id)) {
          ($this_unread_cnt) = $sth->fetchrow_array();
        }
        else {
          my $detail_msg = $sth->errstr;
          _logSystemError($dbh, $user_id, $detail_msg, 'Unable to get number of unread message(s)');
        }        
        $sth->finish;

        push @result, {'group_id' => $this_group_id, 'group_name' => $this_group_name, 'group_type' => $this_group_type, 'group_role' => $this_group_role,
                       'unread_cnt' => $this_unread_cnt};
      }      
    }    
  }
  
  return @result;
}


#-- Note: Since 'snedMessage' involves multiple tables updating, so it is better to run it within SQL transaction protection. i.e.: Start a SQL --#
#--       transaction session, then execute 'snedMessage', and determine whether commit or rollback database operations by returned value.      --# 
sub sendMessage {
  my ($dbh, $user_id, $group_id, $message, $fileloc, $op_flag, $op_user_id, $op_msg) = @_;
  my ($ok, $msg, $msg_id, $encrypt_key, @members);
  
  $ok = 1;
  $msg = '';

  #-- Step 1: Gather group member list --#
  @members = getMessageGroupMembers($dbh, $group_id);
  
  #-- Step 2: Add message record --# 
  ($ok, $msg, $msg_id) = _addMessageRecord($dbh, $user_id, $group_id, $message, $fileloc, $op_flag, $op_user_id, $op_msg);
  
  #-- Step 3: Delivery message to all members (include message sender) --#
  if ($ok) {
    foreach my $rec (@members) {
      my $this_member_id = $rec->{'user_id'};
      
      ($ok, $msg) = _deliverMessage($dbh, $msg_id, $user_id, $this_member_id);
      
      if ($ok && $this_member_id != $user_id) {     # No need to inform message sender
        #-- If a member is offline, and user_list.inform_new_msg = 1, then he/she will be informed. --#
        if (_needToInformMember($dbh, $this_member_id)) {
          #-- Note: Since email sending is a very slow process, so we put record in a queue, another background process will send out --#
          #--       email to inform group member accordingly.                                                                         --#
          ($ok, $msg) = _addNewMessageInformQueueRec($dbh, $this_member_id);          
        }        
      }
      
      last if (!$ok);
    }    
  }
  else {
    #-- If it is unable to create a new message record, but related attached file is existed, deleted it. --#  
    if (-f $fileloc) {
      unlink $fileloc;
    }    
  }
  
  return ($ok, $msg);  
}


sub getMessageGroupMembers {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT a.user_id, b.user_name, b.user_alias, b.name, a.group_role
    FROM group_member a, user_list b
    WHERE a.user_id = b.user_id
      AND b.status = 'A'
      AND group_id = ?
    ORDER BY a.group_role DESC, b.user_name, b.user_alias  
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'user_id' => $data[0], 'username' => $data[1], 'alias' => $data[2], 'name' => $data[3], 'group_role' => $data[4]};
    }    
  }
  $sth->finish;
  
  return @result;  
}


sub _addMessageRecord {
  my ($dbh, $user_id, $group_id, $message, $fileloc, $op_flag, $op_user_id, $op_msg) = @_;
  my ($ok, $msg, $xok, $sql, $sth, $msg_id, $key, $encrypted_msg, $encrypted_op_msg);
  
  $ok = 1;
  $msg = '';
  $msg_id = 0;
  
  $user_id += 0;
  $group_id += 0;
  $op_user_id += 0;
  $message = allTrim($message);
  $fileloc = allTrim($fileloc);
  $op_flag = allTrim($op_flag);
  $op_msg = allTrim($op_msg);
  
  #-- Get group message encryption key --#
  ($ok, $msg, $key) = _getMessageGroupKey($dbh, $group_id);
    
  #-- Encrypt message --#
  if ($ok) {
    ($ok, $encrypted_msg) = _encrypt_str($message, $key);            # Defined on sm_user.pl
    if (!$ok) {
      $msg = "Unable to encrypt message, process is failure.";
    }    
  }
    
  if ($ok) {
    if ($op_flag eq 'R') {
      #-- Message reply --#
      if (utf8_length($op_msg) > 30) {                               # Defined on sm_webenv.pl
        $op_msg = utf8_substring($op_msg, 0, 30) . '...';            # Defined on sm_webenv.pl
      }
      #-- Note: The process should go on, even this process is failure. --#
      ($xok, $encrypted_op_msg) = _encrypt_str($op_msg, $key);       # Defined on sm_user.pl
    }
    
    #-- Create message record --#
    $sql = <<__SQL;
    INSERT INTO message
    (group_id, sender_id, send_time, send_status, msg, fileloc, op_flag, op_user_id, op_msg)
    VALUES
    (?, ?, CURRENT_TIMESTAMP(), 'S', ?, ?, ?, ?, ?)
__SQL
  
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $user_id, $encrypted_msg, $fileloc, $op_flag, $op_user_id, $encrypted_op_msg)) {
      $msg = "Unable to add message. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  
    if ($ok) {
      $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
      if ($sth->execute()) {
        ($msg_id) = $sth->fetchrow_array();
        if ($msg_id <= 0) {
          $msg = "Unable to retrieve the message id by unknown reason";
          $ok = 0;
        }      
      }
      else {
        $msg = "Unable to retrieve the message id. Error: " . $sth->errstr;
        $ok = 0;
      }
      $sth->finish;
    }
  }
  
  if ($ok) {
    #-- Process will go on even this function is failure --# 
    _updateGroupRefreshToken($dbh, $group_id);
  }
    
  return ($ok, $msg, $msg_id);
}


sub _getMessageGroupKey {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, $sql, $sth, $key);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  SELECT encrypt_key
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($key) = $sth->fetchrow_array();    
  }
  else {
    $msg = "Unable to get message group encryption key. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg, $key);
}


sub _updateGroupRefreshToken {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, $sql, $sth, $token);
  
  $ok = 1;
  $msg = '';
  $token = _generateRandomStr('A', 16);          # Defined on sm_webenv.pl
  
  $sql = <<__SQL;
  UPDATE msg_group
    SET refresh_token = ?
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($token, $group_id)) {
    $msg = "Unable to update message group refresh token. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub _deliverMessage {
  my ($dbh, $msg_id, $sender_id, $receiver_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  if ($sender_id == $receiver_id) {
    $sql = <<__SQL;
    INSERT INTO msg_tx
    (msg_id, receiver_id, read_status, read_time)
    VALUES
    (?, ?, 'R', CURRENT_TIMESTAMP())
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($msg_id, $sender_id)) {
      $msg = "Unable to deliver message. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  else {
    $sql = <<__SQL;
    INSERT INTO msg_tx
    (msg_id, receiver_id, read_status)
    VALUES
    (?, ?, 'U')
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($msg_id, $receiver_id)) {
      $msg = "Unable to deliver message. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}


sub _needToInformMember {
  my ($dbh, $member_id) = @_;
  my ($accept_inform, $online, $has_inform_rec, $result);
  
  #-- Step 1: Check whether the member accept new message inform --#
  $accept_inform = _isUserAcceptInform($dbh, $member_id);
  
  if ($accept_inform) {
    #-- Step 2: Check whether the member is currently online --#
    $online = _isUserOnline($dbh, $member_id);
    
    if ($online) {
      $result = 0;
    }
    else {
      #-- Step 3: Check whether the member has already had wait-for-inform record.
      $has_inform_rec = _hasInformRec($dbh, $member_id);
      $result = ($has_inform_rec)? 0 : 1;
    }
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub _isUserAcceptInform {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT inform_new_msg
    FROM user_list
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub _isUserOnline {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $sess_until, $result);
  
  $sql = <<__SQL;
  SELECT MAX(sess_until) AS last_sess
    FROM web_session
    WHERE user_id = ?
      AND status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($sess_until) = $sth->fetchrow_array();
    $sess_until = allTrim($sess_until);
    if ($sess_until ne '') {
      $result = (_isTimeLimitPassed($dbh, $sess_until, '00:00:00.00'))? 0 : 1;         # Defined on sm_user.pl
    }
    else {
      $result = 0;
    }
  }
  else {
    #-- Assume user is offline --#
    $result = 0;
  }
  
  return $result;
}


sub _hasInformRec {
  my ($dbh, $member_id) = @_;
  my ($sql, $sth, $cnt, $result);

  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM new_msg_inform
    WHERE user_id = ?
      AND (status = 'W'
       OR (status = 'E'
      AND try_cnt < 3))
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($member_id)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 1 : 0;
  }
  else {
    #-- Assume the user has no wait-for-inform record --#
    $result = 0;
  }
  
  return $result;
}


sub _addNewMessageInformQueueRec {
  my ($dbh, $member_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO new_msg_inform
  (user_id, period, status, try_cnt)
  VALUES
  (?, CURRENT_TIMESTAMP(), 'W', 0)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($member_id)) {
    $msg = "Unable to create new message inform queue record. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    _setUserInformFlag($dbh, $member_id, 0);         # '0' = Reject new inform email. 
  }  
  
  return ($ok, $msg);
}


sub _setUserInformFlag {
  my ($dbh, $member_id, $flag) = @_;
  my ($ok, $msg, $sql, $sth);
 
  $ok = 1;
  $msg = '';

  $sql = <<__SQL;
  UPDATE user_list
    SET inform_new_msg = ?
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($flag, $member_id)) {
    $msg = "Unable to update new message inform flag. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getMessageGroupName {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, $result);
  
  $result = '';
  
  $sql = <<__SQL;
  SELECT group_name
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($result) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return $result;  
}


sub getPrevGroupMessage {
  my ($dbh, $group_id, $user_id, $first_msg_id, $rows_limit) = @_;
  my ($ok, $msg, $sql, $sth, $key, @sql_params, @result);
  
  $ok = 1;
  $msg = '';
  
  $group_id += 0;
  $user_id += 0;
  $first_msg_id += 0;
  $rows_limit += 0;
  
  #-- Step 1: Check validity of passed parameters --#
  if ($group_id <= 0 || $user_id <= 0 || $first_msg_id <= 0 || $rows_limit <= 0) {
    $msg = "Invalid parameter(s) is/are found. Parameters: group id = $group_id, user id = $user_id, first message id = $first_msg_id, message block size = $rows_limit.";
    $ok = 0;
  }
  
  if ($ok) {
    #-- Step 2: Get group message decryption key --#
    $sql = <<__SQL;
    SELECT encrypt_key
      FROM msg_group
      WHERE group_id = ?
__SQL
  
    $sth = $dbh->prepare($sql);
    if ($sth->execute($group_id)) {
      ($key) = $sth->fetchrow_array();    
    }
    else {
      $msg = "Unable to get message group encryption key (group id = $group_id). Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }

  if ($ok) {
    #-- Step 2: Get messages --#
    $sql = <<__SQL;
    SELECT a.msg_id, a.sender_id, b.user_name, b.user_alias, a.send_time, DATE(a.send_time) AS s_date, TIME(a.send_time) AS s_time,
           TIME_FORMAT(TIME(a.send_time), '%r') AS s_time_12, TIMEDIFF(CURRENT_TIMESTAMP(), a.send_time) AS t_diff, WEEKDAY(a.send_time) AS wday,
           a.msg, a.fileloc, a.op_flag, a.op_user_id, a.op_msg, b.status, CASE WHEN c.user_id is null THEN 0 ELSE 1 END AS is_member,
           CASE WHEN d.read_status = 'U' THEN 1 ELSE 0 END AS is_new_msg
      FROM message a LEFT OUTER JOIN group_member c ON a.group_id = c.group_id AND a.sender_id = c.user_id, user_list b, msg_tx d
      WHERE a.sender_id = b.user_id
        AND a.msg_id = d.msg_id 
        AND a.group_id = ?
        AND d.receiver_id = ?
        AND a.msg_id < ?
      ORDER BY a.send_time DESC
      LIMIT $rows_limit
__SQL
    
    @sql_params = ($group_id, $user_id, $first_msg_id);
    #-- Since it has many different ways to extract messages, but returned data set format is equal, so function '_gatherMessage' is created --#
    #-- to return message data set which is formed by same method in order to reduce possible error in the future.                           --#
    ($ok, $msg, @result) = _gatherMessage($dbh, $sql, $key, $group_id, $user_id, \@sql_params);    
  }
  
  return ($ok, $msg, @result);
}


sub getGroupMessage {
  my ($dbh, $group_id, $user_id, $m_params_ref) = @_;
  my ($ok, $msg, $sql, $sth, $new_msg_only, $rows_limit, $f_m_id, $key, $sql_filter, $data_set_rows, $sort_order, %m_params, @sql_params, @result);
  
  $ok = 1;
  $msg = '';
  
  %m_params = %$m_params_ref;  
  $new_msg_only = $m_params{'new_msg_only'} + 0;    # 0 = load all messages, 1 = Load unread messages only.
  $rows_limit = $m_params{'rows_limit'} + 0;        # It means to get last '$rows_limit' messages, if it is larger than zero.
  $f_m_id = $m_params{'f_m_id'} + 0;                # ID of the first message which has already loaded.
  
  $data_set_rows = ($rows_limit > 0 && $f_m_id <= 0)? "LIMIT $rows_limit" : '';       # Note: It is MariaDB / MySQL specified syntax. It may need to be changed if use another database engine.
  $sort_order = ($rows_limit > 0)? 'DESC' : '';
  $sql_filter = ($new_msg_only == 1)? " AND d.read_status = 'U' " : '';
  $sql_filter .= ($f_m_id > 0)? " AND a.msg_id >= $f_m_id " : "";
  
  #-- Step 1: Get group message decryption key --#
  $sql = <<__SQL;
  SELECT encrypt_key
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($key) = $sth->fetchrow_array();    
  }
  else {
    $msg = "Unable to get message group encryption key (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Step 2: Get messages --#
    $sql = <<__SQL;
    SELECT a.msg_id, a.sender_id, b.user_name, b.user_alias, a.send_time, DATE(a.send_time) AS s_date, TIME(a.send_time) AS s_time,
           TIME_FORMAT(TIME(a.send_time), '%r') AS s_time_12, TIMEDIFF(CURRENT_TIMESTAMP(), a.send_time) AS t_diff, WEEKDAY(a.send_time) AS wday,
           a.msg, a.fileloc, a.op_flag, a.op_user_id, a.op_msg, b.status, CASE WHEN c.user_id is null THEN 0 ELSE 1 END AS is_member,
           CASE WHEN d.read_status = 'U' THEN 1 ELSE 0 END AS is_new_msg
      FROM message a LEFT OUTER JOIN group_member c ON a.group_id = c.group_id AND a.sender_id = c.user_id, user_list b, msg_tx d
      WHERE a.sender_id = b.user_id
        AND a.msg_id = d.msg_id 
        AND a.group_id = ?
        AND d.receiver_id = ?
        $sql_filter
      ORDER BY a.send_time $sort_order
      $data_set_rows
__SQL

    if ($rows_limit > 0) {
      my $data_set = $sql;
      
      $sql = <<__SQL;
      SELECT *
        FROM ($data_set) data_set
        ORDER BY send_time ASC
__SQL
    }
    
    @sql_params = ($group_id, $user_id);
    #-- Since it has many different ways to extract messages, but returned data set format is equal, so function '_gatherMessage' is created --#
    #-- to return message data set which is formed by same method in order to reduce possible error in the future.                           --#
    ($ok, $msg, @result) = _gatherMessage($dbh, $sql, $key, $group_id, $user_id, \@sql_params);
  }
  
  if ($ok) {
    _markMessagesAreRead($dbh, $group_id, $user_id);    
  }
  else {
    _logSystemError($dbh, $user_id, $msg, "getGroupMessage error");
  }
    
  return @result;
}


sub _12HourTimeFormat {
  my ($given_time) = @_;     # Note: $given_time must be in 12 hours time format.
  my ($time, $hh, $mm, $ampm, $result, @parts);
  
  @parts = split(' ', $given_time);
  $time = allTrim($parts[0]);
  $ampm = allTrim($parts[1]);
  
  if ($time ne '' && $ampm ne '') {
    @parts = split(':', $time);
    $hh = allTrim($parts[0] + 0);
    $mm = allTrim($parts[1]);
    $result = "$hh:$mm $ampm";     # Format: hour:minute AM/PM
  }
  else {
    $result = $given_time;
  }
  
  return $result;
}


sub _descFromNow {
  my ($time_diff) = @_;
  my ($hr, $min, $sec, $result, @dateparts);
  
  @dateparts = split(':', $time_diff);
  $hr = $dateparts[0] + 0;
  $min = $dateparts[1] + 0;
  $sec = $dateparts[2] + 0;
  
  #-- Only interpret time difference within 60 minutes --#
  if ($hr == 0) {
    if ($sec >= 30) {
      $min++;
    }
    
    if ($min == 0) {
      $result = "Just now";
    }
    else {
      $result = "$min min ago";  
    }    
  }
  else {
    $result = '';
  }
  
  return $result;
}


sub _descWeekDay {
  my ($mysql_week_day_no) = @_;
  my ($result);
  
  if ($mysql_week_day_no == 0) {
    $result = 'Mon';
  }
  elsif ($mysql_week_day_no == 1) {
    $result = 'Tue';
  }
  elsif ($mysql_week_day_no == 2) {
    $result = 'Wed';
  }
  elsif ($mysql_week_day_no == 3) {
    $result = 'Thu';
  }
  elsif ($mysql_week_day_no == 4) {
    $result = 'Fri';
  }
  elsif ($mysql_week_day_no == 5) {
    $result = 'Sat';
  }
  elsif ($mysql_week_day_no == 6) {
    $result = 'Sun';
  }
  else {
    $result = '';
  }
  
  return $result;
}


sub _gatherMessage {
  my ($dbh, $sql, $key, $group_id, $user_id, $sql_params_ref) = @_;
  my ($ok, $msg, $sth, $dbx, $p_num, $dev_type, $dev_name, $is_iOS, @sql_params, @result);
  
  $ok = 1;
  $msg = '';
  $dbx = dbconnect($COOKIE_MSG);
  ($dev_type, $dev_name) = detectClientDevice();        # Defined on sm_webenv.pl
  $is_iOS = (lc($dev_name) =~ /iphone|ipad|ipod/)? 1 : 0;
  
  @sql_params = ($sql_params_ref ne undef)? @$sql_params_ref : ();
  
  $sth = $dbh->prepare($sql);
  $p_num = 1;
  foreach my $this_param (@sql_params) {
    $sth->bind_param($p_num, $this_param);
    $p_num++;
  }
  
  if ($sth->execute) {
    #-- Note: Data field position on the passed SQL command must be the same. Otherwise, incorrect result will be otained. --#
    my $err_msg = '';
    while (my @data = $sth->fetchrow_array()) {
      my $msg_id = $data[0];
      my $is_my_msg = ($data[1] == $user_id)? 1 : 0;           # It means that $user is the sender of this message.
      my $sender_id = $data[1] + 0;
      my $sender = (allTrim($data[3]) ne '')? $data[3] : $data[2];
      my $s_datetime = $data[4];
      my $s_date = $data[5];
      my $s_time = $data[6];
      my $s_time_12 = _12HourTimeFormat($data[7]);
      my $from_now = _descFromNow($data[8]);
      my $week_day = _descWeekDay($data[9]);        
      my $encrypted_msg = $data[10];
      my ($this_ok, $this_message) = (allTrim($encrypted_msg) ne '')? _decrypt_str($encrypted_msg, $key) : (1, '');               # Defined on sm_user.pl
      my $fileloc = allTrim($data[11]);
      my $op_flag = allTrim($data[12]);
      my $op_user_id = $data[13] + 0;
      my $op_user = ($op_user_id > 0)? getUserName($dbx, $op_user_id) : '';                                                       # Defined on sm_user.pl
      my $encrypted_op_msg = $data[14];
      my ($this_op_ok, $this_op_msg) = (allTrim($encrypted_op_msg) ne '')? _decrypt_str($encrypted_op_msg, $key) : (1, '');       # Defined on sm_user.pl
      my $user_status = $data[15];
      my $is_member = $data[16] + 0;
      my $is_new_msg = $data[17] + 0;
      my $this_msg_30 = (utf8_length($this_message) > 30)? utf8_substring($this_message, 0, 30) . '...' : $this_message;          # 1. Defined on sm_webenv.pl, 2. This data is prepared for message replying operation.
      my ($filename, $dirs, $suffix) = ($fileloc ne '')? fileNameParser($fileloc) : ('', '', '');                                 # Defined on sm_webenv.pl 
      my $file_type = ($fileloc ne '')? findFileType($dbx, $suffix) : '';                                                         # Defined on sm_webenv.pl
      my $file_link = '';
        
      if ($fileloc ne '') {
        if (lc($file_type) eq 'image') {
          my $thumbnail_file = "$ITN_TN_PATH/$filename.jpg";
          my $thumbnail = (-f $thumbnail_file)? "/data/thumbnail/$filename.jpg" : "/data/$filename$suffix";
            
          #-- Note: style="display:block;" for image object is used to restrict the image within a table cell --#
          $file_link = <<__HTML;
          <a href="/data/$filename$suffix" target="_blank"><img style="display:block;" src="$thumbnail" width="100%"></a>      
__HTML
        }
        elsif ($file_type =~ /audio/) {
          #-- Since HTML5 multimedia files handling is not consistent, so that it needs to provide a download link below <audio> --#
          #-- object, so that users still have chance to listen the audio file by downloading it.                                --#
          my $download_link = <<__HTML;
          <br><a href="/data/$filename$suffix" target="_blank">Download Audio</a>
__HTML
          
          $file_link = <<__HTML;
          <audio controls>
            <source src="/data/$filename$suffix" type="$file_type"/>
            <!-- Fallback content //-->
            <p><a href="/data/$filename$suffix" target="_blank"><img src="/images/folder.png" height="100px"></a><br>$filename$suffix</p>
          </audio>
          $download_link
__HTML
        }
        elsif ($file_type =~ /video/) {
          #-- Since HTML5 multimedia files handling is not consistent, so that it needs to provide a download link below <video> --#
          #-- object, so that users still have chance to view the video file by downloading it.                                  --#
          my $download_link = <<__HTML;
          <br><a href="/data/$filename$suffix" target="_blank">Download Video</a><br>
__HTML
          
          $file_link = <<__HTML;
          <video controls width="100%" preload="meta">
            <source src="/data/$filename$suffix" type="$file_type"/>
            <!-- Fallback content //-->
            <p><a href="/data/$filename$suffix" target="_blank"><img src="/images/folder.png" height="100px"></a><br>$filename$suffix</p>
          </video>
          $download_link
__HTML
        }          
        else {
          $file_link = <<__HTML;
          <a href="/data/$filename$suffix" target="_blank"><img src="/images/folder.png" height="100px"></a><br>$filename$suffix     
__HTML
        }
      }
                
      if (!$this_ok) {
        $this_message = "Error: Original message decryption error, please report to your referrer for supporting.";
        $err_msg .= "Unable to decrypt message (message id = $msg_id). \n";
        $ok = 0;          
      }
      else {
        $this_message =~ s/\n/<br>/g;
        $this_op_msg =~ s/\n/<br>/g;
        $this_msg_30 =~ s/'/¡/g;         # All single quote characters are replaced by '¡', so that it can be passed to javascript function without error.
        #-- Make URL link(s) on message alive --#
        $this_message =~ s/(http:\/\/\S+)/<a href=\"$1\" target=new>$1<\/a>/g;
        $this_message =~ s/(https:\/\/\S+)/<a href=\"$1\" target=new>$1<\/a>/g;
      }
      
      push @result, {'msg_id' => $msg_id, 'is_my_msg' => $is_my_msg, 'sender_id' => $sender_id, 'sender' => $sender, 's_datetime' => $s_datetime,
                     's_date' => $s_date, 's_time' => $s_time, 's_time_12' => $s_time_12, 'from_now' => $from_now, 'week_day' => $week_day,
                     'message' => $this_message, 'fileloc' => $fileloc, 'file_link' => $file_link, 'op_flag' => $op_flag, 'op_user_id' => $op_user_id,
                     'op_user' => $op_user, 'op_msg' => $this_op_msg, 'user_status' => $user_status, 'is_member' => $is_member, 'is_new_msg' => $is_new_msg,
                     'msg_30' => $this_msg_30};
    }
      
    if (!$ok) {
      $msg = $err_msg;
    }      
  }    
  else {
    $msg = "Unable to retrieve messages (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  dbclose($dbx);
   
  return ($ok, $msg, @result);
}


sub _markMessagesAreRead {
  my ($dbh, $group_id, $user_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';

  $sql = <<__SQL;
  UPDATE msg_tx JOIN message ON msg_tx.msg_id = message.msg_id
    SET msg_tx.read_status = 'R',
        msg_tx.read_time = CURRENT_TIMESTAMP()
    WHERE message.group_id = ?
      AND msg_tx.receiver_id = ?
      AND msg_tx.read_status = 'U';
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id, $user_id)) {
    $msg = "Unable to mark message as read (group_id = $group_id, receiver_id = $user_id. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  if (!$ok) {
    _logSystemError($dbh, $user_id, $msg, "Unable to mark message read status");
  }

  return ($ok, $msg); 
}


sub getMessageUpdateToken {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, $result);
  
  $result = '';
  
  $sql = <<__SQL;
  SELECT refresh_token, group_id
    FROM msg_group
    WHERE group_id = ? 
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    my ($r_token, $g_id) = $sth->fetchrow_array();
    $g_id += 0;
    if ($g_id == $group_id) {
      $result = allTrim($r_token);  
    }
    else {
      #-- Message group has been deleted or system error has been found --#
      $result = "group_deleted";
    }
  }
  
  return $result;
}


sub getLastSentMessage {
  my ($dbh, $group_id, $sender_id) = @_;
  my ($ok, $msg, $sql, $sth, $key, $last_sent_msg_id, @sql_params, @result);
  
  $ok = 1;
  $msg = '';
    
  #-- Step 1: Get group message decryption key --#
  $sql = <<__SQL;
  SELECT encrypt_key
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($key) = $sth->fetchrow_array();    
  }
  else {
    $msg = "Unable to get message group encryption key (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Step 2: Find the last sent message ID --#
    $sql = <<__SQL;
    SELECT MAX(msg_id) AS max_msg_id
      FROM message
      WHERE group_id = ?
        AND sender_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($group_id, $sender_id)) {
      ($last_sent_msg_id) = $sth->fetchrow_array();
      $last_sent_msg_id += 0;
    }
    else {
      $msg = "Unable to get the ID of your last sent message. Error: " .$sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }  

  if ($ok) {
    $sql = <<__SQL;
    SELECT a.msg_id, a.sender_id, b.user_name, b.user_alias, a.send_time, DATE(a.send_time) AS s_date, TIME(a.send_time) AS s_time, 
           TIME_FORMAT(TIME(a.send_time), '%r') AS s_time_12, TIMEDIFF(CURRENT_TIMESTAMP(), a.send_time) AS t_diff, WEEKDAY(a.send_time) AS wday, 
           a.msg, a.fileloc, a.op_flag, a.op_user_id, a.op_msg,  b.status, CASE WHEN c.user_id is null THEN 0 ELSE 1 END AS is_member, 
           CASE WHEN d.read_status = 'U' THEN 1 ELSE 0 END AS is_new_msg   
      FROM message a LEFT OUTER JOIN group_member c ON a.group_id = c.group_id AND a.sender_id = c.user_id, user_list b, msg_tx d
      WHERE a.sender_id = b.user_id 
        AND a.msg_id = d.msg_id
        AND a.sender_id = d.receiver_id
        AND d.read_status = 'R'         
        AND a.group_id = ? 
        AND d.msg_id = ?
__SQL

    @sql_params = ($group_id, $last_sent_msg_id);
    #-- Since it has many different ways to extract messages, but returned data set format is equal, so function '_gatherMessage' is created --#
    #-- to return message data set which is formed by same method in order to reduce possible error in the future.                           --#
    ($ok, $msg, @result) = _gatherMessage($dbh, $sql, $key, $group_id, $sender_id, \@sql_params);
  }  
  
  if (!$ok) {
    _logSystemError($dbh, $sender_id, $msg, "getLastSentMessage error");
  }
  
  return @result;
}


sub deleteMessage {
  my ($dbh, $group_id, $msg_id) = @_;
  my ($ok, $msg, $fileloc, $fname, $dirs, $fext, $tn_file);
  
  $ok = 1;
  $msg = '';
  
  if ($dbh) {
    #-- Step 1: Check whether any physical file related to this message --#
    $fileloc = _getMessageAttachment($dbh, $msg_id);
    
    #-- Step 2: Delete message --#
    if (startTransaction($dbh)) {
      ($ok, $msg) = _removeMessage($dbh, $msg_id);
      
      if ($ok) {
        ($ok, $msg) = _removeMessageDeliveryRecord($dbh, $msg_id);
      }
      
      if ($ok) {
        ($ok, $msg) = _updateGroupRefreshToken($dbh, $group_id);
      }
      
      if ($ok) {
        #-- Delete attached file (if any), after database is updated sucessfully. --#
        if (allTrim($fileloc) ne '') {
          if (-f $fileloc) {
            unlink $fileloc;
          }
          
          ($fname, $dirs, $fext) = fileNameParser($fileloc);
          $tn_file = "$ITN_TN_PATH/$fname.jpg";
          if (-f $tn_file) {
            unlink $tn_file;
          }
        }

        commitTransaction($dbh);      
      }
      else {
        rollbackTransaction($dbh);
      }      
    }
    else {
      $msg = "Unable to start SQL transaction session.";
      $ok = 0;
    }
  }
  else {
    $msg = "Invalid database handle is found.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub _getMessageAttachment {
  my ($dbh, $msg_id) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT fileloc
    FROM message
    WHERE msg_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($msg_id)) {
    ($result) = $sth->fetchrow_array();
  }
  else {
    $result = '';
  }
  $sth->finish;
  
  return $result;
}


sub _removeMessage {
  my ($dbh, $msg_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM message
    WHERE msg_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($msg_id)) {
    $msg = "Unable to delete message. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  return ($ok, $msg);  
}


sub _removeMessageDeliveryRecord {
  my ($dbh, $msg_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM msg_tx
    WHERE msg_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($msg_id)) {
    $msg = "Unable to delete message delivery records. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  return ($ok, $msg);  
}


sub getGroupRole {
  my ($dbh, $group_id, $user_id) = @_;
  my ($sql, $sth, $result);
  
  $result = 0;
  
  $sql = <<__SQL;
  SELECT group_role
    FROM group_member
    WHERE group_id = ?
      AND user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $user_id)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  $sth->finish;
  
  return $result;
}


sub getGroupName {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, $result);
  
  $result = '';
  
  $sql = <<__SQL;
  SELECT group_name
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($result) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return $result;
}


sub isPrivateGroup {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT group_type
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = -1;
  }
  $sth->finish;
  
  return $result;
}


sub deleteMessageGroup {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, @attached_files);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    @attached_files = _getGroupAttachedFiles($dbh, $group_id);
    
    ($ok, $msg) = _removeGroup($dbh, $group_id);
    
    if ($ok) {
      ($ok, $msg) = _removeGroupMember($dbh, $group_id);
    }
    
    if ($ok) {
      #-- Delete records on two tables by one shoot --#
      ($ok, $msg) = _removeGroupMessageAndDeliveryHistory($dbh, $group_id);
    }
            
    if ($ok) {
      commitTransaction($dbh);      
      _deleteGroupAttachedFiles(\@attached_files) if (scalar(@attached_files) > 0);  
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "Unable to start SQL transaction session, process is aborted.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub _getGroupAttachedFiles {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, @result);
  
  @result = ();
  
  $sql = <<__SQL;
  SELECT fileloc
    FROM message
    WHERE group_id = ?
      AND TRIM(fileloc) <> '';
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    while (my $this_fileloc = $sth->fetchrow_array()) {
      push @result, $this_fileloc;
    }    
  }
  $sth->finish;
  
  return @result;
}


sub _removeGroup {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, $sql, $sth);

  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id)) {
    $msg = "Unable to delete message group (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub _removeGroupMember {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM group_member
    WHERE group_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id)) {
    $msg = "Unable to delete group members (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);  
}


sub _removeGroupMessageAndDeliveryHistory {
  my ($dbh, $group_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE message, msg_tx
    FROM message INNER JOIN msg_tx ON message.msg_id = msg_tx.msg_id
    WHERE message.group_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id)) {
    $msg = "Unable to delete group message and delivery history (group id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub _deleteGroupAttachedFiles {
  my ($attached_files_ref) = @_;
  
  my @attached_files = @$attached_files_ref;
  foreach my $this_file (@attached_files) {
    if (-f $this_file) {
      unlink $this_file;
    }
  }
}


sub getAllMessageGroups {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, @result);
  
  @result = ();
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT group_id, group_name
      FROM msg_group 
      ORDER BY group_name  
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
      while (my @data = $sth->fetchrow_array()) {
        push @result, {'group_id' => $data[0], 'group_name' => $data[1]};
      }
    }
    else {
      my $msg = $sth->errstr;      
      _logSystemError($dbh, $user_id, $msg, "getAllMessageGroups error");
    }    
  }
  
  return @result;
}


sub deleteUserInformRecord {
  my ($dbh, $user_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM new_msg_inform
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id)) {
    $msg = "Unable to remove new message inform record(s). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub loadGroupMeesagesForNewMember {
  my ($dbh, $group_id, $member_id) = @_;
  my ($ok, $msg, $sql, $sth, @miss_messages);
  
  $ok = 1;
  $msg = '';
  
  #-- Step 1: Find out all missing messages of a group for the new member --#
  $sql = <<__SQL;
  SELECT DISTINCT a.msg_id
    FROM message a, msg_tx b
    WHERE a.msg_id = b.msg_id
      AND a.group_id = ?
      AND b.receiver_id <> ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $member_id)) {
    while (my ($this_msg_id) = $sth->fetchrow_array()) {
      push @miss_messages, $this_msg_id; 
    }
  }
  else {
    $msg = "Unable to load old messages for the new member. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  #-- Step 2: Recreate message delivery transaction records for the new member --#
  if ($ok) {
    foreach my $this_msg_id (@miss_messages) {
      $sql = <<__SQL;
      INSERT INTO msg_tx
      (msg_id, receiver_id, read_status)
      VALUES
      (?, ?, 'U')
__SQL

      $sth = $dbh->prepare($sql);
      if (!$sth->execute($this_msg_id, $member_id)) {
        #-- Don't stop process even error is found --#
        $msg .= "Unable to recall old message (msg_id = $this_msg_id) for new member (id = $member_id). Error: " . $sth->errstr . "\n";
        $ok = 0;
      }
      $sth->finish;
    }
  }
  
  return ($ok, $msg);
}


sub getGroupSettings {
  my ($dbh, $group_id) = @_;
  my ($sql, $sth, @data, %result);
  
  $sql = <<__SQL;
  SELECT group_name, group_type, msg_auto_delete, delete_after_read, encrypt_key, status, refresh_token
    FROM msg_group
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    @data = $sth->fetchrow_array();
    %result = ('group_id' => $group_id, 'group_name' => $data[0], 'group_type' => $data[1] + 0, 'msg_auto_delete' => $data[2] + 0,
               'delete_after_read' => $data[3] + 0, 'encrypt_key' => $data[4], 'status' => $data[5], 'refresh_token' => $data[6]);
  }
  $sth->finish;
  
  return %result;
}


sub getGroupType {
  my ($dbh, $group_id) = @_;
  my ($group_type, %group_profile);
  
  %group_profile = getGroupSettings($dbh, $group_id);
  $group_type = $group_profile{'group_type'} + 0;
  
  return $group_type;
}


sub uploadFileToMessageGroup {
  my ($dbh, $group_id, $sender_id, $ul_ftype, $ul_file, $caption, $op_flag, $op_user_id, $op_msg) = @_;
  my ($ok, $msg, $filename, $tn_filename, $audio_converter);  
  
  $ok = 1;
  $msg = '';
  $filename = '';
  
  #-- Load up the audio converter --#
  $audio_converter = loadAudioConverter($dbh); 
    
  #-- Step 1: Move the upload file to the right place --#
  ($ok, $msg, $filename) = fileUpload($ul_file);                                    # Defined on sm_webenv.pl
  
  #-- Step 2: If it is image file, create thumbnail for it. --#
  if ($ok) {
    if ($ul_ftype eq 'photo') {
      ($ok, $msg, $tn_filename) = createThumbnail($filename, $ITN_TN_PATH);         # Defined on sm_webenv.pl 
    }
    else {
      my ($f_name, $dirs, $suffix) = fileNameParser($filename);                     # Defined on sm_webenv.pl
      my $file_type = findFileType($dbh, $suffix);                                  # Defined on sm_webenv.pl 
      if ($file_type eq 'image') {
        ($ok, $msg, $tn_filename) = createThumbnail($filename, $ITN_TN_PATH);       # Defined on sm_webenv.pl
      }
      elsif ($file_type eq 'aud_convertable' && $audio_converter ne '') {
        #-- Note: Once an audio file is converted successfully, the value of $filename will be changed, --#
        #--       and the original audio file will be deleted.                                          --#
        ($ok, $msg, $filename) = convertAudioFile($audio_converter, $filename);     # Defined on sm_webenv.pl
        #-- If file conversion is failure, the original file name will be returned. So, just upload it  --#
        #-- as an attached file. i.e. The file uploading process will go on even file conversion is     --#
        #-- failure.                                                                                    --#
        $ok = 1; $msg = '';
      }
    }    
  }
  
  #-- Step 3: Send out message --#
  if ($ok) {
    ($ok, $msg) = sendMessage($dbh, $sender_id, $group_id, $caption, $filename, $op_flag, $op_user_id, $op_msg);     
  }
  
  return ($ok, $msg);
}


sub loadAudioConverter {
  my ($dbh) = @_;
  my ($audio_converter_setting, $audio_converter, $result, @parts);
  
  $audio_converter_setting = allTrim(getSysSettingValue($dbh, 'audio_converter'));                   # Defined on sm_webenv.pl
  if ($audio_converter_setting ne '') {
    @parts = split(' ', $audio_converter_setting);
    $audio_converter = allTrim($parts[0]);       # Audio converter (with full path) must be the first data                                              
    if ((-f $audio_converter) && $audio_converter_setting =~ /{input_file}/ && $audio_converter_setting =~ /{output_file}/) {
      $result = $audio_converter_setting;
    }
    else {
      $result = '';  
    }
  }
  else {
    $result = '';
  }
  
  return $result;
}


1;