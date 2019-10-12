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
# Program: /www/itnews/cgi-pl/admin/maintain_sys_settings.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-08      DW              Maintain a list of system settings which
#                                               are applied to entire system to control
#                                               system behavior.
# V1.0.01       2019-01-29      DW              Add follow up checking as system settings
#                                               is added or modified.
# V1.0.02       2019-10-12      DW              Function 'isHeSysAdmin' is moved to sm_user.pl
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $op = paramAntiXSS('op');                               # A = Add, E = Edit, D = Delete.
my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $sys_key_old = paramAntiXSS('sys_key_old');             # Original system key. It is used for system settings amendment operation.
my $sys_key = paramAntiXSS('sys_key');                     # System key.
my $sys_value = paramAntiXSS('sys_value');                 # Value of system key.

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @key_list = ();
my %key_dtl;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($op eq 'A') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = addNewSysSetting($dbh, $sys_key, $sys_value);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_sys_settings.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_sys_settings.pl?op=A");
      }        
    }
    else {
      printNewSysKeyForm();
    }
  }
  elsif ($op eq 'E') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = modifySysSetting($dbh, $sys_key_old, $sys_key, $sys_value);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_sys_settings.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_sys_settings.pl?op=E");
      }        
    }
    else {
      %key_dtl = getSysSettingDetails($dbh, $sys_key);
      printSysSettingEditForm(\%key_dtl);
    }  
  }
  elsif ($op eq 'D') {
    my ($ok, $msg) = deleteSysSetting($dbh, $sys_key);
    if (!$ok) {
      alert($msg);
    }  
    redirectTo("/cgi-pl/admin/maintain_sys_settings.pl");
  }
  else {
    @key_list = getSysSettingList($dbh);
    printSysSettingList(\@key_list); 
  }
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. --#
  redirectTo("/cgi-pl/admin/system_setup.pl");      
}

dbclose($dbh);
#-- End Main Section --#


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>

  <script>
    function goBack() {
      window.location.href = "/cgi-pl/admin/system_setup.pl";
    }
  
    function goHome() {
      window.location.href = "/cgi-pl/msg/message.pl";
    }
    
    function addSysSetting() {
      document.getElementById("op").value = "A";
      document.getElementById("frm_sys_set").submit();          
    }
    
    function editSysSetting(sys_key) {
      document.getElementById("op").value = "E";
      document.getElementById("sys_key").value = sys_key;
      document.getElementById("frm_sys_set").submit();      
    }
    
    function deleteSysSetting(sys_key) {
      if (confirm("Are you sure to delete this system setting?")) {
        document.getElementById("op").value = "D";
        document.getElementById("sys_key").value = sys_key;
        document.getElementById("frm_sys_set").submit();
      }
    }
    
    function saveSysSetting() {
      var sys_key = allTrim(\$('#sys_key').val());
      var sys_value = allTrim(\$('#sys_value').val());
      
      if (sys_key == "") {
        alert("Please input key of system setting before saving");
        \$('#sys_key').focus();
        return false;
      }
      
      if (sys_value == "") {
        alert("Please input key value of system setting before saving");
        \$('#sys_value').focus();
        return false;
      }
                  
      \$('#oper_mode').val("S");
      \$('#frm_sys_set').submit();      
    }
  </script>
__JS
}


sub addNewSysSetting {
  my ($dbh, $sys_key, $sys_value) = @_;
  my ($ok, $msg);
  
  if (isSysSettingExist($dbh, $sys_key)) {
    ($ok, $msg) = updateSysSetting($dbh, $sys_key, $sys_key, $sys_value);
  }
  else {
    ($ok, $msg) = addSysSetting($dbh, $sys_key, $sys_value);
  }

  if ($ok) {
    followUpReminder($dbh, $sys_key, $sys_value);
  }
  
  return ($ok, $msg);
}


sub isSysSettingExist {
  my ($dbh, $sys_key) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $cnt = $result = 0;
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM sys_settings
    WHERE sys_key = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($sys_key)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 1 : 0;
  }
  $sth->finish;
  
  return $result;
}


sub addSysSetting {
  my ($dbh, $sys_key, $sys_value) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO sys_settings
  (sys_key, sys_value)
  VALUES
  (?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sys_key, $sys_value)) {
    $msg = "Unable to add system setting $sys_key. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub printNewSysKeyForm {
  my ($html);
  
  $html = <<__HTML;
  <form id="frm_sys_set" name="frm_sys_set" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/admin/maintain_sys_settings.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Add Sys Setting</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <label for="sys_key">Key:</label>
      <input type=text id="sys_key" name="sys_key" value="$sys_key" maxlength=64>
      <label for="sys_value">Value:</label>
      <input type=text id="sys_value" name="sys_value" value="$sys_value" maxlength=512>
      <br>
      <input type=button id="save" name="save" value="Save" onClick="saveSysSetting()">
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub modifySysSetting {
  my ($dbh, $sys_key_old, $sys_key, $sys_value) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if ($sys_key_old eq $sys_key) {
    ($ok, $msg) = updateSysSetting($dbh, $sys_key, $sys_key, $sys_value);  
  }
  else {
    if (isSysSettingExist($dbh, $sys_key)) {
      if (startTransaction($dbh)) {
        ($ok, $msg) = deleteSysSetting($dbh, $sys_key_old);
        
        if ($ok) {
          ($ok, $msg) = updateSysSetting($dbh, $sys_key, $sys_key, $sys_value);
        }
        
        if ($ok) {
          commitTransaction($dbh);
        }
        else {
          rollbackTransaction($dbh);
        }
      }
      else {
        $msg = "Unable to start SQL transaction session, system setting record cannot be updated.";
        $ok = 0;
      }
    }
    else {
      ($ok, $msg) = updateSysSetting($dbh, $sys_key_old, $sys_key, $sys_value);
    }
  }
  
  if ($ok) {
    followUpReminder($dbh, $sys_key, $sys_value);
  }
    
  return ($ok, $msg);
}


sub updateSysSetting {
  my ($dbh, $sys_key_old, $sys_key, $sys_value) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE sys_settings
    SET sys_key = ?,
        sys_value = ?
    WHERE sys_key = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sys_key, $sys_value, $sys_key_old)) {
    $msg = "Unable to update system setting $sys_key_old. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub followUpReminder {
  my ($dbh, $sys_key, $sys_value) = @_;
  
  $sys_key = allTrim($sys_key);
  
  if ($sys_key eq 'connection_mode') {
    $sys_value += 0;
    
    if ($sys_value == 0 || $sys_value == 2 || $sys_value == 3) {
      my $gmail_worker_cnt = checkGmailWorkerNumber($dbh);
      
      if ($gmail_worker_cnt == 0) {
        alert("You have changed 'connection_mode' to $sys_value, but you have no Gmail worker, please add at least one Gmail worker, or SMS is going to malfunction.");
      }      
    }
    
    if ($sys_value == 0 || $sys_value == 3) {
      my $user_no_email_cnt = checkHowManyUserWithoutEmail($dbh);
      
      if ($user_no_email_cnt > 0) {
        my $alert_msg = ($user_no_email_cnt == 1) ? "It has 1 user without email address, he/she can't login to SMS in connection mode $sys_value" :
                        "There are $user_no_email_cnt users without email address, they can't login to SMS in connection mode $sys_value";
        alert($alert_msg);
      }
    }
  }
}


sub checkGmailWorkerNumber {
  my ($dbh) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*)
    FROM sys_email_sender
    WHERE status = 'A';
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub checkHowManyUserWithoutEmail {
  my ($dbh) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*)
    FROM user_list
    WHERE (TRIM(email) = '' OR email IS NULL)
      AND status = 'A';
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub getSysSettingDetails {
  my ($dbh, $sys_key) = @_;
  my ($sql, $sth, @data, %result);
  
  $sql = <<__SQL;
  SELECT sys_value
    FROM sys_settings
    WHERE sys_key = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($sys_key)) {
    @data = $sth->fetchrow_array();
    %result = ('sys_key' => $sys_key, 'sys_value' => $data[0]);
  }
  $sth->finish;
  
  return %result;
}


sub printSysSettingEditForm {
  my ($key_dtl_ref) = @_;
  my ($html, %key_dtl);
  
  %key_dtl = %$key_dtl_ref;
  
  $html = <<__HTML;
  <form id="frm_sys_set" name="frm_sys_set" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="sys_key_old" name="sys_key_old" value="$sys_key">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/admin/maintain_sys_settings.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Edit Sys Setting</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <label for="sys_key">Key:</label>
      <input type=text id="sys_key" name="sys_key" value="$key_dtl{'sys_key'}" maxlength=64>
      <label for="sys_value">Value:</label>
      <input type=text id="sys_value" name="sys_value" value="$key_dtl{'sys_value'}" maxlength=512>
      <br>
      <input type=button id="save" name="save" value="Save" onClick="saveSysSetting()">  
    </div>
  </div>
  </form>
__HTML

  print $html;
}


sub deleteSysSetting {
  my ($dbh, $sys_key) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM sys_settings
    WHERE sys_key = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sys_key)) {
    $msg = "Unable to delete system setting $sys_key. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getSysSettingList {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT sys_key, sys_value
    FROM sys_settings
    ORDER BY sys_key
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'sys_key' => $data[0], 'sys_value' => $data[1]};
    }
  }
  $sth->finish;
  
  return @result;
}


sub printSysSettingList {
  my ($key_list_ref) = @_;
  my ($html, @key_list);
  
  @key_list = @$key_list_ref;
  
  $html = <<__HTML;
  <form id="frm_sys_set" name="frm_sys_set" action="" method="post">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="sys_key" name="sys_key" value="">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack()" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>System Settings</h1>
      <a href="javascript:goHome()" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed">
      <thead>
        <tr style="background-color:lightblue">
          <td width=30% align=center valign=center><b>Key</b></td>
          <td width=50% align=center valign=center><b>Value</b></td>
          <td align=center valign=center><b>Delete</b></td>
        </tr>
      </thead>
      <tbody>
__HTML
  
  foreach my $rec (@key_list) {
    my $this_sys_key = $rec->{'sys_key'};
    my $this_sys_value = $rec->{'sys_value'};
    
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td valign=center style="word-wrap:break-word">
            <a href="javascript:editSysSetting('$this_sys_key')">$this_sys_key</a>
          </td>
          <td valign=center style="word-wrap:break-word">
            <a href="javascript:editSysSetting('$this_sys_key')">$this_sys_value</a>
          </td>
          <td align=center valign=center>
            <input type=button id="del_ss" name="del_ss" data-icon="delete" data-iconpos="notext" onClick="deleteSysSetting('$this_sys_key')">
          </td>
        </tr>
__HTML
  }
  
  $html .= <<__HTML;
        <tr style="background-color:lightblue"><td align=center colspan=3>End</td></tr>
      </tbody>
      </table>
    </div>

    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0 style="table-layout:fixed">
      <thead></thead>
      <tbody>
        <tr>
          <td align=center valign=center><input type=button id="add_ss" name="add_ss" value="Add System Setting" data-icon="plus" onClick="addSysSetting()"></td>
        </tr>
      </tbody>
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}

