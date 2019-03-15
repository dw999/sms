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
# Program: /www/itnews/cgi-pl/msg/add_private_group.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-21      AY              Create private (1 to 1) messaging group.
# V1.0.01       2018-08-06      AY              Let default settings of private group is
#                                               to remove message automatically, and period
#                                               for read-after-deletion is 1 minute.
# V1.0.02       2018-08-21      AY              Invite group member by using alias only.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));        # 'S' = Save, others go to data input form.
my $group_name = allTrim(paramAntiXSS('group_name'));
my $auto_delete = paramAntiXSS('auto_delete') + 0;
my $delete_after = paramAntiXSS('delete_after') + 0;       # Unit in minute.
my $member = allTrim(paramAntiXSS('member'));              # It could be user name, user alias or email address to identify an user.

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

if ($oper_mode eq 'S') {
  my ($ok, $msg) = (1, '');
  
  ($ok, $msg) = createPrivateGroup($dbh, $user_id, $group_name, $member, $auto_delete, $delete_after);
  
  if ($ok) {
    redirectTo("/cgi-pl/msg/message.pl");
  }
  else {
    alert($msg);
    redirectTo("/cgi-pl/msg/add_private_group.pl?group_name=$group_name&member=$member");
  }  
}
else {
  $auto_delete = 1;      # Default action is to delete already read message automatically.
  
  printJavascriptSection();  
  printDataInputForm();
}

dbclose($dbh);
#-- End Main Section --#


sub createPrivateGroup {
  my ($dbh, $user_id, $group_name, $member, $auto_delete, $delete_after) = @_;
  my ($ok, $msg, $member_id, $group_id);
  
  #-- Ensure $delete_after is an integer --#
  $delete_after = sprintf("%d", $delete_after);
    
  #-- Step 1: Try to get user id of the invited person --#
  $member_id = findMember($dbh, $member);
  if ($member_id <= 0) {
    $msg = "The person you want to invit doesn't exist.";
    $ok = 0;
  }
  else {
    if ($member_id == $user_id) {
      $msg = "Guy, don't invit yourself to form a private group.";
      $ok = 0;    
    }
    else {
      $ok = 1;
      $msg = '';    
    }
  }
  
  if ($ok) {    
    if (startTransaction($dbh)) {
      #-- Step 2: Create the group --#
      ($ok, $msg, $group_id) = addPrivateGroup($dbh, $group_name, $auto_delete, $delete_after);
      
      if ($ok) {
        #-- Step 3: Add all persons to group member table --#
        ($ok, $msg) = addGroupMember($dbh, $group_id, $user_id, $member_id);
      }
      
      if ($ok) {
        #-- Step 4: Send the first message on behalf of the group creator to the invited person --#
        ($ok, $msg) = sendMemberFirstMessage($dbh, $group_id, $user_id);
      }
      
      if ($ok) {
        commitTransaction($dbh);
      }
      else {
        rollbackTransaction($dbh);
      }
    }
    else {
      $msg = "Unable to start SQL transaction session, process cannot proceed.";
      $ok = 0;
    }
    
    if (!$ok) {
      _logSystemError($dbh, $user_id, $msg, 'Private group creation failure');        # Defined on sm_user.pl
    }    
  }
  
  return ($ok, $msg);
}


sub findMember {
  my ($dbh, $member) = @_;
  my ($sql, $sth, $member_id);
  
  $member_id = 0;

#  $sql = <<__SQL;
#  SELECT user_id
#    FROM user_list
#    WHERE (user_name = ?
#       OR user_alias = ?
#       OR email = ?)
#      AND status = 'A' 
#__SQL

  $sql = <<__SQL;
  SELECT user_id
    FROM user_list
    WHERE user_alias = ?
      AND status = 'A' 
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($member)) {
    ($member_id) = $sth->fetchrow_array();
    $member_id += 0;
  }
  $sth->finish;
    
  return $member_id;  
}


sub addPrivateGroup {
  my ($dbh, $group_name, $auto_delete, $delete_after) = @_;
  my ($sql, $sth, $ok, $msg, $group_id, $encrypt_key);
  
  $ok = 1;
  $msg = '';  
  $group_id = 0;
  $encrypt_key = _generateRandomStr('A', 32);                # Defined on sm_webenv.pl
  
  $sql = <<__SQL;
  INSERT INTO msg_group
  (group_name, group_type, msg_auto_delete, delete_after_read, encrypt_key, status, refresh_token)
  VALUES
  (?, 1, ?, ?, ?, 'A', '')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_name, $auto_delete, $delete_after, $encrypt_key)) {
    $msg = "Unable to create group. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Retrieve the newly added group id --#
    $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
    if ($sth->execute()) {
      ($group_id) = $sth->fetchrow_array();
      if ($group_id <= 0) {
        $msg = "Unable to retrieve newly created group id by unknown reason.";
        $ok = 0;
      }      
    }
    else {
      $msg = "Unable to retrieve newly created group id. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }

  return ($ok, $msg, $group_id);  
}


sub addGroupMember {
  my ($dbh, $group_id, $user_id, $member_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  #-- This is the group administrator --#
  $sql = <<__SQL;
  INSERT INTO group_member
  (group_id, user_id, group_role)
  VALUES
  (?, ?, '1')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id, $user_id)) {
    $msg = "Unable to add group administrator. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  if ($ok) {    
    #-- This is the group member, the only member. --#
    $sql = <<__SQL;
    INSERT INTO group_member
    (group_id, user_id, group_role)
    VALUES
    (?, ?, '0')
__SQL
  
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $member_id)) {
      $msg = "Unable to add group member. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;    
  }
  
  return ($ok, $msg);
}


sub sendMemberFirstMessage {
  my ($dbh, $group_id, $user_id) = @_;
  my ($ok, $msg, $message);
  
  $message = "You are invited to join this group.";
  ($ok, $msg) = sendMessage($dbh, $user_id, $group_id, $message);               # Defined on sm_msglib.pl
  
  return ($ok, $msg);
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>    

  <script>
    \$(document).on("pagecreate", function() {
      \$("#group_name").focus();
      \$("#input_grp").show();
    });
    
    //*-- Define event handler of checkbox 'auto_delete' --*//
    \$(function() {
      \$("#auto_delete").on('change', function() {
        if (this.checked) {
          \$("#input_grp").show();
        }
        else {
          \$("#input_grp").hide();
        }
      })      
    });    

    function createGroup() {
      var this_group_name = allTrim(document.getElementById("group_name").value);
      if (this_group_name == "") {
        alert("Group name is compulsory");
        document.getElementById("group_name").focus();
        return false;
      }
      
      var this_member = allTrim(document.getElementById("member").value);
      if (this_member == "") {
        alert("Person to be invited is compulsory");
        document.getElementById("member").focus();
        return false;        
      }
      
      var is_checked = document.getElementById("auto_delete").checked;
      if (is_checked == false) {
        document.getElementById("auto_delete").value = 0;
        document.getElementById("delete_after").value = 0;
      }
      else {
        document.getElementById("auto_delete").value = 1;
        var da = parseInt(document.getElementById("delete_after").value, 10);
        if (isNaN(da) || (da < 1 || da > 30)) {
          document.getElementById("delete_after").value = 1;
        }
      }
      
      document.getElementById("oper_mode").value = "S";
      document.getElementById("frmAddPgrp").submit();
    }    
  </script>
__JS
}


sub printDataInputForm {
  my ($html, $checked);
  
  $checked = ($auto_delete == 1)? 'checked' : '';
  
  $html = <<__HTML;
  <form id="frmAddPgrp" name="frmAddPgrp" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>		
			<h1>Add Private Group</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <label for="group_name">Group name:</label>
      <input type="text" id="group_name" name="group_name" value="$group_name">
      <label for="member">Who is invited (alias):</label>      
      <input type="text" id="member" name="member" value="$member">
      <label for="auto_delete">Auto delete read message:</label>
      <input type="checkbox" data-role="flipswitch" id="auto_delete" name="auto_delete" value="$auto_delete" $checked>
      <br>
      <div id="input_grp">
        <label for="delete_after" id="lbl_delete_after">Delete after read (minute):</label>
        <input type="range" id="delete_after" name="delete_after" value="1" min="1" max="30">
      </div>
      <br>
      <input type="button" id="save" name="save" value="Create" onClick="createGroup();">
    </div>
  </div>  
  </form>
__HTML
  
  print $html;
}
