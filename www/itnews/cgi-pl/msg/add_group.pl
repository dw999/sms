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
# Program: /www/itnews/cgi-pl/msg/add_group.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-26      DW              Create messaging group.
# V1.0.01       2018-07-30      DW              Add group messages periodic clearing option.
# V1.0.02       2018-08-21      DW              Invite group member by using alias only.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);                          # Function 'getGroupMembers' need database connection, so it is put in here.

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));        # 'S' = Save, others go to data input form.
my $group_name = allTrim(paramAntiXSS('group_name'));
my $msg_auto_delete = paramAntiXSS('msg_auto_delete') + 0; # 0 = Keep group messages, 1 = Allow messages to be deleted automatically.
my @members = getGroupMembers($dbh);                           

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

if ($oper_mode eq 'S') {
  my ($ok, $msg) = (1, '');
  
  if (scalar(@members) > 0) {
    ($ok, $msg) = createMessageGroup($dbh, $user_id, $group_name, $msg_auto_delete, \@members);
  
    if ($ok) {
      redirectTo("/cgi-pl/msg/message.pl");
    }
    else {
      alert($msg);
      redirectTo("/cgi-pl/msg/add_group.pl?group_name=$group_name");
    }
  }
  else {
    alert("Unable to find invited person(s), try again.");
    redirectTo("/cgi-pl/msg/add_group.pl?group_name=$group_name");
  }
}
else {
  printJavascriptSection();  
  printDataInputForm();  
}

dbclose($dbh);
#-- End Main Section --#


sub getGroupMembers {
  my ($dbh) = @_;
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /member_/) {
      my $this_member = $params{$this_key};
      if (allTrim($this_member) ne '') {
        my $this_member_id = findMember($dbh, $this_member);
        if ($this_member_id > 0 && $this_member_id != $user_id) {     # Don't invit yourself.
          push @result, {'member_id' => $this_member_id, 'member' => $this_member};  
        }
      }
    }    
  }
  
  return @result;
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


sub createMessageGroup {
  my ($dbh, $user_id, $group_name, $msg_auto_delete, $members_ref) = @_;
  my ($ok, $msg, $group_id);

  $ok = 1;
  $msg = '';
  $group_id = 0;

  if (startTransaction($dbh)) {
    ($ok, $msg, $group_id) = addMessageGroup($dbh, $group_name, $msg_auto_delete);
    
    if ($ok) {
      ($ok, $msg) = addGroupMember($dbh, $group_id, $user_id, $members_ref);
    }
    
    if ($ok) {
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
    _logSystemError($dbh, $user_id, $msg, 'Message group creation failure');        # Defined on sm_user.pl
  }      
  
  return ($ok, $msg);
}


sub addMessageGroup {
  my ($dbh, $group_name, $msg_auto_delete) = @_;
  my ($sql, $sth, $ok, $msg, $group_id, $encrypt_key);
  
  $ok = 1;
  $msg = '';  
  $group_id = 0;
  $encrypt_key = _generateRandomStr('A', 32);                # Defined on sm_webenv.pl
  
  $sql = <<__SQL;
  INSERT INTO msg_group
  (group_name, group_type, msg_auto_delete, delete_after_read, encrypt_key, status, refresh_token)
  VALUES
  (?, 0, ?, 0, ?, 'A', '')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_name, $msg_auto_delete, $encrypt_key)) {
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
  my ($dbh, $group_id, $user_id, $members_ref) = @_;
  my ($ok, $msg, $sql, $sth, @members);
  
  $ok = 1;
  $msg = '';
  @members = @$members_ref;
  
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
    #-- Group member(s) --#
    foreach my $rec (@members) {
      my $this_member_id = $rec->{'member_id'} + 0;
      
      $sql = <<__SQL;
      INSERT INTO group_member
      (group_id, user_id, group_role)
      VALUES
      (?, ?, '0')
__SQL
  
      $sth = $dbh->prepare($sql);
      if (!$sth->execute($group_id, $this_member_id)) {
        $msg = "Unable to add group member. Error: " . $sth->errstr;
        $ok = 0;
      }
      $sth->finish;    
      
      last if (!$ok);
    }
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
    var idx = 0;
   
    \$(document).on("pagecreate", function() {
      for (i = 1; i <= 5; i++) {
        addMember(); 
      }    
    });
        
    function addMember() {
      idx++;
      
      \$("#member_section").each(
        function() {
          var id = "member_" + idx;
          var row = "<tr id='row_" + idx + "'><td><input type='text' id='" + id + "' name='" + id + "'/></td></tr>";
          //*-- Note: jQuery mobile API function ".enhanceWithin()" will apply default CSS settings to dynamically added objects --*//
          \$(this).append(row).enhanceWithin();
        }
      );      
    }
        
    function deleteMember() {
      if (idx > 1) {
        \$("#row_" + idx).remove();
        idx--;
      }
    }
    
    function createGroup() {
      if (dataSetOk()) {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frmAddGrp").submit();
      }
    }
    
    function dataSetOk() {
      var this_group_name = allTrim(document.getElementById("group_name").value);
      if (this_group_name == "") {
        alert("Group name is compulsory");
        document.getElementById("group_name").focus();
        return false;
      }

      //*-- Note: As checkbox object 'auto_delete' is unchecked, it's value will not passed to the server as form is submitted. --*//
      //*--       Therefore, we need another variable 'msg_auto_delete' to pass data to the back-end.                           --*//
      var is_checked = document.getElementById("auto_delete").checked;
      if (is_checked) {
        document.getElementById("msg_auto_delete").value = 1;
      }
      else {
        document.getElementById("msg_auto_delete").value = 0;
      }
      
      var count = 0;    
      for (i = 1; i <= idx; i++) {
        if (document.getElementById("member_" + i) != null) {
          var member = allTrim(document.getElementById("member_" + i).value);
          if (member != "") {
            count++;  
          }
        }
      }
      
      if (count == 0) {
        alert("You should invite at least one person to create a message group");
        return false;
      }
      
      return true;
    }
  </script>
__JS
}


sub printDataInputForm {
  my ($html);
    
  $html = <<__HTML;
  <form id="frmAddGrp" name="frmAddGrp" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="msg_auto_delete" name="msg_auto_delete" value="">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>		
			<h1>Add Group</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <label for="group_name">Group name:</label>
      <input type="text" id="group_name" name="group_name" value="$group_name">

      <label for="auto_delete" style="width:60%; display:inline">Clear messages periodically:</label>
      <input type="checkbox" data-role="flipswitch" id="auto_delete" name="auto_delete" value="" checked>
      
      <table id="member_section" width=100% cellpadding=0 cellspacing=0>
      <thead>
        <tr><td>Who will be invited (alias):</td></tr>
      </thead>
      <tbody>
        <!-- Rows will be added dynamically //-->
      </tbody>  
      </table>
            
      <table width=100%>
      <thead><tr><td colspan=3></td></tr></thead>
      <tbody>
      <tr>  
        <td align=left width=35%><a href="#" data-icon="plus" data-role="button" data-ajax="false" onClick="addMember();">More</a></td>
        <td></td>
        <td align=right width=35%><a href="#" data-icon="minus" data-role="button" data-ajax="false" onClick="deleteMember();">Less</a></td>
      </tr>
      </tbody>
      </table>
      
      <br>
      <input type="button" id="save" name="save" value="Create" onClick="createGroup();">            
    </div>
  </div>  
  </form>  
__HTML
  
  print $html;
}
