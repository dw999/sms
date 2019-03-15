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
# Program: /www/itnews/cgi-pl/msg/edit_group_profile.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-11      AY              Message group profile maintenance.
# V1.0.01       2018-08-08      AY              Add auto-deletion setup for private group.
# V1.0.02       2018-08-21      AY              Only accept alias as add new group member(s).
# V1.0.03       2018-09-03      AY              Add manual inform option to group administrator.
# V1.0.04       2018-09-12      AY              Improve manual user inform message sending notification.
# V1.0.05       2018-09-21      AY              Take care message loading on demand by passing the ID of
#                                               the first load message to the calling program. Note: this
#                                               data is stored on local storage of the web browser.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use WWW::Telegram::BotAPI;
use Encode qw(decode encode);
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $op = paramAntiXSS('op') + 0;                           # Operation ID
my $group_id = paramAntiXSS('g_id') + 0;                   # Message group ID
my $oper_mode = paramAntiXSS('oper_mode');                 # Operation mode of a specified operation.
my $group_name = paramAntiXSS('group_name');               # Message group name
my $member_id = paramAntiXSS('member_id') + 0;             # Group member ID. It is used for group exit.
my $auto_delete = paramAntiXSS('auto_delete') + 0;         # 0 = Not auto-deletion, 1 = Auto-deletion. Used for private group setup. 
my $delete_after = paramAntiXSS('delete_after') + 0;       # Unit in minute. Used for private group setup.
my $inform_message = paramAntiXSS('inform_message');       # Message is sent to group members manually.

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

my $ok = 1;
my $msg = '';

printJavascriptSection();

if ($op == 1) {        # Amend group name
  if ($oper_mode eq 'S') {
    ($ok, $msg) = updateGroupName($dbh, $group_id, $group_name);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }    
  }
  else {
    printAmendGroupNameForm();
  }
}
elsif ($op == 2) {     # List group member
  printGroupMemberList();
}
elsif ($op == 3) {     # Add member
  if ($oper_mode eq 'S') {
    my @new_members = getNewMembersToBeAdded($dbh, $group_id);
    
    ($ok, $msg) = addNewMemberToGroup($dbh, $group_id, \@new_members);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();      
    }
  }
  else {
    printAddMemberForm();  
  }
}
elsif ($op == 4) {     # Delete member
  if ($oper_mode eq 'S') {
    my @delete_members = getMembersToBeDeleted();
    
    ($ok, $msg) = deleteGroupMember($dbh, $group_id, \@delete_members);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }    
  }
  else {
    printDeleteMemberForm();  
  }  
}
elsif ($op == 5) {     # Exit group
  ($ok, $msg) = quitMessageGroup($dbh, $group_id, $member_id);
  if ($ok) {
    clearLocalData();
    redirectTo("/cgi-pl/msg/message.pl");
  }
  else {
    alert($msg);
    back();
  }
}
elsif ($op == 6) {     # Promote group member to group administrator
  if ($oper_mode eq 'S') {
    my @promote_members = getPromoteMembers();
    
    ($ok, $msg) = promoteMemberToGroupAdmin($dbh, $group_id, \@promote_members);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }    
  }
  else {
    printPromoteMemberForm(); 
  }
}
elsif ($op == 7) {     # Demote group administrator to group member
  if ($oper_mode eq 'S') {
    my @demote_members = getDemoteMembers();
    
    ($ok, $msg) = demoteGroupAdmin($dbh, $group_id, \@demote_members);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }        
  }
  else {
    printDemoteAdminForm(); 
  }  
}
elsif ($op == 8) {     # Auto deletion setup for private group
  if ($oper_mode eq 'S') {
    ($ok, $msg) = updateAutoDeleteSettings($dbh, $group_id, $auto_delete, $delete_after);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }            
  }
  else {
    if (isPrivateGroup($dbh, $group_id)) {      # Defined on sm_msglib.pl
      printAutoDeleteSetupForm($dbh, $group_id);
    }
    else {
      alert("Sorry, this is not a private group!");
      returnToCaller($group_id);
    }
  }
}
elsif ($op == 9) {     # Manually send notification to group members
  if ($oper_mode eq 'S') {
    ($ok, $msg) = sendGroupInformMessage($dbh, $group_id, $inform_message);
    if ($ok) {
      returnToCaller($group_id);
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    printSendInformMessageForm($dbh, $group_id);
  }
}

dbclose($dbh);
#-- End Main Section --#


sub printJavascriptSection {
  my ($init_op3);
  
  if ($op == 3) {
    $init_op3 = <<__JS;
    \$(document).on("pagecreate", function() {
      for (i = 1; i <= 5; i++) {
        addMemberInput(); 
      }    
    });    
__JS
  }
    
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    var idx = 0;
   
    $init_op3 
           
    function addMemberInput() {
      idx++;
      
      \$("#member_section").each(
        function() {
          var id = "new_member_" + idx;
          var row = "<tr id='row_" + idx + "'><td><input type='text' id='" + id + "' name='" + id + "'/></td></tr>";
          //*-- Note: jQuery mobile API function ".enhanceWithin()" will apply default CSS settings to dynamically added objects --*//
          \$(this).append(row).enhanceWithin();
        }
      );      
    }
    
    function deleteMemberInput() {
      if (idx > 1) {
        \$("#row_" + idx).remove();
        idx--;
      }
    }  
  
    //*-- This method may let the last message missing, so it needs to reload entire page. --#
    //function goBack() {
    //  parent.history.back();
    //}
    
    function goBack() {
      var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);      
      //*-- Due the limitation on iOS, so I use cookies to store cross page data, instead to use localStorage. --*// 
      var f_m_id = (is_iOS == false)? getLocalStoredItem("m_id") : Cookies.get("m_id");
      var top_id = (is_iOS == false)? getLocalStoredItem("top_id") : Cookies.get("top_id");
      window.location.href = "/cgi-pl/msg/do_sms.pl?g_id=$group_id&f_m_id=" + f_m_id + "&top_id=" + top_id;
    }
  
    function updateGroupName() {
      var g_name = \$("#group_name").val();
      
      if (allTrim(g_name) == "") {
        alert("Group name should not be blank");
        \$("#group_name").focus();
      }
      else {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();
      }
    }
    
    function addNewMember() {
      if (newMemberDataSetOk()) {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();
      }
    }
          
    function newMemberDataSetOk() {
      var count = 0;    
      for (i = 1; i <= idx; i++) {
        if (document.getElementById("new_member_" + i) != null) {
          var member = allTrim(document.getElementById("new_member_" + i).value);
          if (member != "") {
            count++;  
          }
        }
      }
      
      if (count == 0) {
        alert("You should invit at least one person to create a message group");
        return false;
      }
      
      return true;
    }
    
    function deleteMember(cnt) {
      var select_cnt = 0;
    
      for (idx = 1; idx <= cnt; idx++) {
        if (document.getElementById("dm_id_" + idx).checked) {
          select_cnt++;
        }
      }
      
      if (select_cnt == 0) {
        alert("You must select at least one member to proceed");
        return false;
      }
      else {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();
      }
    }
    
    function promoteMember(cnt) {
      var select_cnt = 0;
    
      for (idx = 1; idx <= cnt; idx++) {
        if (document.getElementById("pm_id_" + idx).checked) {
          select_cnt++;
        }
      }
      
      if (select_cnt == 0) {
        alert("You must select at least one member to promote");
        return false;
      }
      else {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();
      }      
    }
    
    function demoteGroupAdmin(cnt) {
      var select_cnt = 0;
    
      for (idx = 1; idx <= cnt; idx++) {
        if (document.getElementById("da_id_" + idx).checked) {
          select_cnt++;
        }
      }
      
      if (select_cnt == 0) {
        alert("You must select at least one group administrator to demote");
        return false;
      }
      else {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();
      }      
    }
    
    function sendInformMessage() {
      var message = allTrim(document.getElementById("inform_message").value);
      if (message == "") {
        alert("Please input notification message before click send button.");
        document.getElementById("inform_message").focus();
      }
      else {
        \$('#to_be_inform').hide();
        \$('#go_inform').show();
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_profile").submit();        
      }
    }    
  </script>
__JS
}


sub returnToCaller {
  my ($group_id) = @_;
 
  print <<__JS;
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
    var f_m_id = (is_iOS == false)? getLocalStoredItem("m_id") : Cookies.get("m_id");        // Defined on common_lib.js : js.cookie.min.js
    var top_id = (is_iOS == false)? getLocalStoredItem("top_id") : Cookies.get("top_id");
    window.location.href = "/cgi-pl/msg/do_sms.pl?g_id=$group_id&f_m_id=" + f_m_id + "&top_id=" + top_id;
  </script>
__JS
}


sub updateGroupName {
  my ($dbh, $group_id, $group_name) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE msg_group
    SET group_name = ?
    WHERE group_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_name, $group_id)) {
    $msg = "Unable to amend group name. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub printAmendGroupNameForm {
  my ($html);
  
  $group_name = (allTrim($group_name) eq '')? getGroupName($dbh, $group_id) : $group_name;       # getGroupName is defined on sm_msglib.pl
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Group Name</h1>
    </div>

    <div data-role="main" class="ui-content">
      <label for="group_name">Group name:</label>
      <input type="text" id="group_name" name="group_name" value="$group_name">
      <br>
      <input type="button" id="save" name="save" value="Change" onClick="updateGroupName();">            
    </div>  
  </div>
  </form>
__HTML

  print $html;
}


sub printGroupMemberList {
  my ($html, @members);
  
  @members = getMessageGroupMembers($dbh, $group_id);      # Defined on sm_msglib.pl
  
  $html = <<__HTML;
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Members</h1>
    </div>

    <div data-role="main" class="ui-content">
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Username / Alias</b></td><td align=center><b>Role</b></td></tr>
      </thead>
      <tbody>
__HTML

  foreach my $rec (@members) {
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_member = ($this_alias eq '')? $this_username : $this_alias; 
    my $this_group_role = ($rec->{'group_role'} == 1)? 'Group Admin' : '';
    
    $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td align=center>$this_member</td>
        <td align=center>$this_group_role</td>
      </tr>
__HTML
  }

  $html .= <<__HTML;
      <tr style="background-color:lightblue; height:22px;"><td colspan=2></td></tr>
      </tbody>  
      </table>
    </div>  
  </div>
__HTML

  print $html;  
}


sub getNewMembersToBeAdded {
  my ($dbh, $group_id) = @_;
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /new_member_/) {
      my $this_member = $params{$this_key};
      if (allTrim($this_member) ne '') {
        my $this_member_id = findAndVerifyNewMember($dbh, $this_member, $group_id);
        if ($this_member_id > 0 && $this_member_id != $user_id) {     # Don't invit yourself.
          my ($this_username, $this_alias) = getMemberDetails($dbh, $this_member_id);
          $this_member = ($this_alias eq '')? $this_username : $this_alias;
          push @result, {'member_id' => $this_member_id, 'member' => $this_member};  
        }
      }
    }    
  }
  
  return @result;
}


sub findAndVerifyNewMember {
  my ($dbh, $member, $group_id) = @_;
  my ($sql, $sth, $member_id);
  
  $member_id = 0;

  #-- Step 1: Try to find the member by his/her alias. --#
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

  if ($member_id > 0) {
    #-- Step 2: If the guy do exist, then check whether he/she has already been member of the group. If he/she is not --#
    #--         group member, grant he/she as a valid candidate. Otherwise, reject him/her.                           --#
    $sql = <<__SQL;
    SELECT COUNT(*) AS cnt
      FROM group_member
      WHERE group_id = ?
        AND user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($group_id, $member_id)) {
      my ($cnt) = $sth->fetchrow_array();
      $member_id = ($cnt > 0)? 0 : $member_id;      
    }
    else {
      #-- If something is wrong, it is better to reject this guy. --# 
      $member_id = 0;
    }
    $sth->finish;
  }  
    
  return $member_id;
}


sub getMemberDetails {
  my ($dbh, $member_id) = @_;
  my ($sql, $sth, $username, $alias);
  
  $username = $alias = '';
  
  $sql = <<__SQL;
  SELECT user_name, user_alias
    FROM user_list
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($member_id)) {
    my @data = $sth->fetchrow_array();
    $username = allTrim($data[0]);
    $alias = allTrim($data[1]);
  }
  
  return ($username, $alias);
}


sub addNewMemberToGroup {
  my ($dbh, $group_id, $new_members_ref) = @_;
  my ($ok, $msg, $sql, $sth, @new_members);
  
  $ok = 1;
  $msg = '';
  
  @new_members = @$new_members_ref;
  foreach my $rec (@new_members) {
    my $member_id = $rec->{'member_id'} + 0;
    my $member = $rec->{'member'};
    my $add_ok = 0;
    
    $sql = <<__SQL;
    INSERT INTO group_member
    (group_id, user_id, group_role)
    VALUES
    (?, ?, 0)
__SQL
    
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $member_id)) {
      #-- Note: The process will go on, even one or more candidate(s) can't be added. --#
      $msg .= "Unable to add $member. Error: " . $sth->errstr . "\n";
      $ok = 0;
    }
    else {
      $add_ok = 1;
    }
    $sth->finish;
    
    if ($add_ok) {
      loadGroupMeesagesForNewMember($dbh, $group_id, $member_id);     # Defined on sm_msglib.pl
    }
        
    if ($add_ok) {
      my $message = "New member $member has joined";
      sendMessage($dbh, $user_id, $group_id, $message);               # Defined on sm_msglib.pl
    }
  }
  
  return ($ok, $msg);
}


sub printAddMemberForm {
  my ($html);
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Add Member</h1>
    </div>

    <div data-role="main" class="ui-content">
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
        <td align=left width=35%><a href="#" data-icon="plus" data-role="button" data-ajax="false" onClick="addMemberInput();">More</a></td>
        <td></td>
        <td align=right width=35%><a href="#" data-icon="minus" data-role="button" data-ajax="false" onClick="deleteMemberInput();">Less</a></td>
      </tr>
      </tbody>
      </table>
      
      <br>
      <input type="button" id="save" name="save" value="Add" onClick="addNewMember();">            
    </div>
  </div>
  </form>
__HTML
 
  print $html; 
}


sub getMembersToBeDeleted {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /dm_id_/) {
      my $this_member_id = $params{$this_key} + 0;
      if ($this_member_id > 0) {
        push @result, $this_member_id;  
      }
    }    
  }
  
  return @result;  
}


sub deleteGroupMember {
  my ($dbh, $group_id, $delete_members_ref) = @_;
  my ($ok, $msg, @delete_members);
  
  $ok = 1;
  $msg = '';  
  @delete_members = @$delete_members_ref;
  
  if (startTransaction($dbh)) {           # Defined on sm_db.pl
    foreach my $this_member_id (@delete_members) {
      ($ok, $msg) = quitMessageGroup($dbh, $group_id, $this_member_id);
      last if (!$ok);
    }
    
    if ($ok) {
      commitTransaction($dbh);            # Defined on sm_db.pl
    }
    else {
      rollbackTransaction($dbh);          # Defined on sm_db.pl
    }    
  }
  else {
    $msg = "Unable to start database transaction session, process is stopped.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub printDeleteMemberForm {
  my ($html, $cnt, $spaces, @members);
  
  @members = getMessageGroupMembers($dbh, $group_id);      # Defined on sm_msglib.pl
  $spaces = '&nbsp;' x 3;
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Delete Member</h1>
    </div>

    <div data-role="main" class="ui-content">
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Username / Alias</b></td><td align=center><b>Role</b></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@members) {
    my $this_user_id = $rec->{'user_id'} + 0;
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_member = ($this_alias eq '')? $this_username : $this_alias; 
    my $this_group_role = ($rec->{'group_role'} == 1)? 'Group Admin' : '';
    
    if ($this_user_id != $user_id) {     # Don't delete yourself
      $cnt++;
      
      $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td>
          <input type="checkbox" id="dm_id_$cnt" name="dm_id_$cnt" value="$this_user_id"><label for="dm_id_$cnt">$this_member</label>
        </td>
        <td align=center>$this_group_role</td>
      </tr>
__HTML
    }
  }

  $html .= <<__HTML;
      </tbody>  
      </table>
      <br>
      <input type="button" id="save" name="save" value="Delete" onClick="deleteMember($cnt);">
    </div>  
  </div>
__HTML

  print $html;
}


sub quitMessageGroup {
  my ($dbh, $group_id, $member_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM group_member
    WHERE group_id = ?
      AND user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id, $member_id)) {
    $msg = "Unable to exit group. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub clearLocalData {
  print <<__JS;
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
    
    if (is_iOS) {
      Cookies.remove("g_id");                                    // Defined on js.cookie.min.js
      Cookies.remove("u_id");
      Cookies.remove("m_id");
    }
    else {
      deleteLocalStoredItem("g_id");                             // Defined on common_lib.js
      deleteLocalStoredItem("u_id");                             
      deleteLocalStoredItem("m_id");                             
    }
  </script>
__JS
}


sub getPromoteMembers {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /pm_id_/) {
      my $this_member_id = $params{$this_key} + 0;
      if ($this_member_id > 0) {
        push @result, $this_member_id;  
      }
    }    
  }
  
  return @result;    
}


sub promoteMemberToGroupAdmin {
  my ($dbh, $group_id, $promote_members_ref) = @_;
  my ($ok, $msg, $sql, $sth, @promote_members);
  
  $ok = 1;
  $msg = '';
  
  @promote_members = @$promote_members_ref;
  foreach my $this_member_id (@promote_members) {
    $sql = <<__SQL;
    UPDATE group_member
      SET group_role = '1'
      WHERE group_id = ?
        AND user_id = ?
__SQL
    
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $this_member_id)) {
      $msg .= "Unable to promote member (id = $this_member_id) to group admin. Error: " . $sth->errstr;
      $ok = 0;
    }
  }

  return ($ok, $msg);  
}


sub getDemoteMembers {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /da_id_/) {
      my $this_member_id = $params{$this_key} + 0;
      if ($this_member_id > 0) {
        push @result, $this_member_id;  
      }
    }    
  }
  
  return @result;  
}


sub demoteGroupAdmin {
  my ($dbh, $group_id, $demote_members_ref) = @_;
  my ($ok, $msg, $sql, $sth, @demote_members);
  
  $ok = 1;
  $msg = '';
  
  @demote_members = @$demote_members_ref;
  foreach my $this_member_id (@demote_members) {
    $sql = <<__SQL;
    UPDATE group_member
      SET group_role = '0'
      WHERE group_id = ?
        AND user_id = ?
__SQL
    
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $this_member_id)) {
      $msg .= "Unable to demote group administrator (id = $this_member_id). Error: " . $sth->errstr;
      $ok = 0;
    }
  }

  return ($ok, $msg);    
}


sub printPromoteMemberForm {
  my ($html, $cnt, $spaces, @members);
  
  @members = getMessageGroupMembers($dbh, $group_id);      # Defined on sm_msglib.pl
  $spaces = '&nbsp;' x 3;
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Promote Member</h1>
    </div>

    <div data-role="main" class="ui-content">
      <b>Select member(s) to become group administrator:</b>
      <br>
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Username / Alias</b></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@members) {
    my $this_user_id = $rec->{'user_id'} + 0;
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_member = ($this_alias eq '')? $this_username : $this_alias; 
    my $this_group_role = $rec->{'group_role'} + 0;
    
    if ($this_user_id != $user_id && $this_group_role == 0) {     # Don't promote yourself, and only ordinary member(s) can be promoted as group admin.
      $cnt++;
      
      $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td>
          <input type="checkbox" id="pm_id_$cnt" name="pm_id_$cnt" value="$this_user_id"><label for="pm_id_$cnt">$this_member</label>
        </td>
      </tr>
__HTML
    }
  }

  if ($cnt > 0) {
    $html .= <<__HTML;
        </tbody>  
        </table>
        <br>
        <input type="button" id="save" name="save" value="Promote" onClick="promoteMember($cnt);">
      </div>  
    </div>
__HTML
  }
  else {
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td>No group member is available to be promoted to group administrator</td>
        </tr>
        </tbody>  
        </table>
      </div>  
    </div>
__HTML
  }
  
  print $html;
}


sub printDemoteAdminForm {
  my ($html, $cnt, $spaces, @members);
  
  @members = getMessageGroupMembers($dbh, $group_id);      # Defined on sm_msglib.pl
  $spaces = '&nbsp;' x 3;
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Demote Admin</h1>
    </div>

    <div data-role="main" class="ui-content">
      <b>Select group administrator(s) to demote:</b>
      <br>    
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr><td></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@members) {
    my $this_user_id = $rec->{'user_id'} + 0;
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_member = ($this_alias eq '')? $this_username : $this_alias; 
    my $this_group_role = $rec->{'group_role'} + 0;
    
    if ($this_user_id != $user_id && $this_group_role == 1) {     # Don't demote yourself, and only group administrator can be demoted.
      $cnt++;
      
      $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td>
          <input type="checkbox" id="da_id_$cnt" name="da_id_$cnt" value="$this_user_id"><label for="da_id_$cnt">$this_member</label>
        </td>
      </tr>
__HTML
    }
  }

  if ($cnt > 0) {
    $html .= <<__HTML;
        </tbody>  
        </table>
        <br>
        <input type="button" id="save" name="save" value="Demote" onClick="demoteGroupAdmin($cnt);">
      </div>  
    </div>
__HTML
  }
  else {
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td>No group administrator is available to be demoted</td>
        </tr>
        </tbody>  
        </table>
      </div>  
    </div>
__HTML
  }
  
  print $html;
}


sub printAutoDeleteSetupForm {
  my ($dbh, $group_id) = @_;
  my ($html, $checked, %group_settings);
  
  %group_settings = getGroupSettings($dbh, $group_id);              # Defined on sm_msglib.pl      
  $auto_delete = $group_settings{'msg_auto_delete'} + 0;
  $delete_after = $group_settings{'delete_after_read'} + 0;
  $checked = ($auto_delete)? 'checked' : '';
    
  $html = <<__HTML;
  <script>
    var val_auto_delete = $auto_delete;
    var val_delete_after = $delete_after;
    
    \$(document).on("pagecreate", function() {
      if (val_auto_delete == 1) {
        \$("#input_grp").show();  
      }
      else {
        \$("#input_grp").hide();
      }      
    });
    
    //*-- Define event handler of checkbox 'auto_delete' --*//
    \$(function() {
      \$("#auto_delete").on('change', function() {
        if (this.checked) {
          if (\$("#delete_after").val() < 1 || \$("#delete_after").val() > 30) {
            \$("#delete_after").val(1);
          }
        
          \$("#input_grp").show();
        }
        else {
          \$("#input_grp").hide();
        }
      })      
    });
    
    function updateAutoDeleteSettings() {
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
      document.getElementById("frm_profile").submit();
    }    
  </script>
__HTML
  
  $html .= <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Auto Delete Setup</h1>
    </div>

    <div data-role="main" class="ui-content">
      <label for="auto_delete">Auto delete read message:</label>
      <input type="checkbox" data-role="flipswitch" id="auto_delete" name="auto_delete" value="$auto_delete" $checked>
      <br>
      <div id="input_grp">
        <label for="delete_after" id="lbl_delete_after">Delete after read (minute):</label>
        <input type="range" id="delete_after" name="delete_after" value="$delete_after" min="1" max="30">
      </div>
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="updateAutoDeleteSettings();">            
    </div>  
  </div>
  </form>
__HTML

  print $html;  
}


sub updateAutoDeleteSettings {
  my ($dbh, $group_id, $auto_delete, $delete_after) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $delete_after = sprintf("%d", $delete_after);
  
  $sql = <<__SQL;
  UPDATE msg_group
    SET msg_auto_delete = ?,
        delete_after_read = ?
    WHERE group_id = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($auto_delete, $delete_after, $group_id)) {
    $msg = "Unable to change auto-delete settings. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub printSendInformMessageForm {
  my ($dbh, $group_id) = @_;
  my ($html);
  
  $inform_message = (allTrim($inform_message) eq '')? "You have important message, please check for it ASAP." : $inform_message;
  
  $html = <<__HTML;
  <form id="frm_profile" name="frm_profile" action="" method="post">
  <input type="hidden" id="op" name="op" value="$op">
  <input type="hidden" id="oper_mode" name="oper_mode" value="">
  <input type="hidden" id="g_id" name="g_id" value="$group_id">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
			<h1>Inform Member</h1>
    </div>

    <div data-role="main" class="ui-content">
      <table id="member_section" width=100% cellpadding=0 cellspacing=0>
      <thead>
        <tr><td><b>Message to be sent:</b></td></tr>
      </thead>
      <tbody>
        <tr>
          <td><textarea id="inform_message" name="inform_message" autofocus data-role="none" style="width:100%; height:150px; max-height:300px;">$inform_message</textarea></td>
        </tr>
        
        <tr><td>&nbsp;</td></tr>
        
        <tr id="to_be_inform">
          <td align=center width=100%><input type="button" id="send" name="send" value="Send" onClick="sendInformMessage();"></td>  
        </tr>
        
        <tr id="go_inform" style="display:none">
          <td align=center valign=center width=100%><img src="/images/files_uploading.gif" width="40px"><br>Sending....</td>
        </tr>
      </tbody>  
      </table>                                    
    </div>
  </div>
  </form>
__HTML
 
  print $html;   
}


sub sendGroupInformMessage {
  my ($dbh, $group_id, $inform_message) = @_;
  my ($ok, $msg, $sql, $sth, $url, $subject, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, @members);
  my ($api, $has_tg_bot, $bot_ok, %tg_bot_profile);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  SELECT DISTINCT a.user_id, a.email, a.tg_id
    FROM user_list a, msg_tx b, message c
    WHERE a.user_id = b.receiver_id
      AND b.msg_id = c.msg_id
      AND c.group_id = ?
      AND b.read_status = 'U'
      AND a.status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @members, {'user_id' => $data[0], 'email' => $data[1], 'tg_id' => $data[2]};
    }    
  }
  $sth->finish;
  
  if (scalar(@members) == 0) {
    alert("All members read all the messages, no need to send out notified message.");
  }
  else {
    $inform_message = decode('utf8', $inform_message);
    
    $url = getSiteDNS($dbh, 'D');                                                                  # Defined on sm_webenv.pl
    $subject = "Important News";
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);           # Defined on sm_webenv.pl
    $body = "$inform_message \n\n$url\n";
    %tg_bot_profile = getTelegramBotProfile($dbh);                                                 # Defined on sm_webenv.pl
    $has_tg_bot = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
    $bot_ok = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
    
    if ($has_tg_bot) {
      $api = WWW::Telegram::BotAPI->new(
        token => $tg_bot_profile{'http_api_token'}
      ) or $bot_ok = 0;
    }
    
    foreach my $rec (@members) {
      my $to_user_id = $rec->{'user_id'} + 0;
      my $to_mail = $rec->{'email'};
      my $tg_id = allTrim($rec->{'tg_id'});          # It is the Telegram chat ID of this SMS user.
      my $tg_err_msg = '';
      
      ($ok, $msg) = sendOutGmail($from_mail, $to_mail, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl
      if (!$ok) {
        _logSystemError($dbh, $to_user_id, $msg, 'sendGroupInformMessage - email');
      }
      
      if ($ok && $bot_ok && $tg_id ne '') {
        eval {
          $api->api_request('sendMessage', {
            chat_id => $tg_id,
            text    => $inform_message
          });
        } or $tg_err_msg = $api->parse_error->{msg};
        
        if ($tg_err_msg ne '') {
          _logSystemError($dbh, $to_user_id, $tg_err_msg, 'sendGroupInformMessage - Telegram');
          $msg = $tg_err_msg;
          $ok = 0;
        }
      }
      
      last if (!$ok);
    }
  }
  
  return ($ok, $msg);
}
