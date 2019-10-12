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
# Program: /www/itnews/cgi-pl/admin/lock_user.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-17      DW              Lock / Unlock user.
# V1.0.01       2018-08-05      DW              If an user is locked, delete all active
#                                               session(s) of that user.
# V1.0.02       2019-10-12      DW              Fix a security loophole by checking whether current user
#                                               is system administrator.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $step = paramAntiXSS('step') + 0;                       # 0 = Select operation, 1 = Select user(s), 2 = Finalize operation.
my $op = paramAntiXSS('op') + 0;                           # 0 = Unknown, 1 = Lock user, 2 = Unlock user.
my @select_users = getSelectedUsers();

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $ip_address = allTrim($user_info{'IP_ADDRESS'});

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($step == 0) {
    printSelectOperationForm();  
  }
  elsif ($step == 1) {
    printSelectUserForm();
  }
  elsif ($step == 2) {
    my ($ok, $msg) = changeStatusForSelectedUsers($dbh, $op, \@select_users);
    if ($ok) {
      redirectTo("/cgi-pl/msg/message.pl");
    }
    else {
      alert($msg);
      back();
    }
  }
}
else {
  if ($user_id > 0) {  
    #-- Something is wrong, the system may be infiltrated by hacker.   --#
    #-- Note: if $user_id <= 0, it is highly possible the user in this --#
    #-- page has been timeout.                                         --#
    lockUserAcct($dbh, $user_id);
    informSysAdmin($dbh, $user_id, $ip_address);
  }
  #-- Expel the suspicious user --#
  redirectTo("/cgi-pl/auth/logout.pl");   
}

dbclose($dbh);
#-- End Main Section --#


sub getSelectedUsers {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /op_user_id_/) {
      my $this_user_id = $params{$this_key} + 0;
      if ($this_user_id > 0) {
        push @result, $this_user_id;  
      }
    }    
  }
  
  return @result; 
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>    

  <script>
    function goStep(to_step, cnt) {
      to_step = parseInt(to_step, 10);
      
      if (to_step == 0 || to_step == 1) {
        document.getElementById("step").value = to_step;
        document.getElementById("frm_lock").submit();
      }
      else {
        if (to_step == 2) {
          if (dataSetValid(cnt)) {
            document.getElementById("step").value = to_step;
            document.getElementById("frm_lock").submit();          
          }
        }              
      }
    }
    
    function dataSetValid(cnt) {
      var this_op = parseInt(document.getElementById("op").value, 10);
      if (this_op != 1 && this_op != 2) {
        alert("Something is wrong, please start over again.");
        return false;
      }

      var select_cnt = 0;
      for (ix = 1; ix <= cnt; ix++) {
        if (document.getElementById("op_user_id_" + ix).checked) {
          select_cnt++;
        }
      }
      
      if (select_cnt == 0) {
        alert("You must select at least one user to proceed");
        return false;
      }
      
      return true;
    }
  </script>
__JS
}


sub printSelectOperationForm {
  my ($html, $step0_lock_check, $step0_unlock_check);
  
  if ($step == 0) {
    $op = ($op <= 0)? 1 : $op; 
    if ($op == 1) {
      $step0_lock_check = "checked";
      $step0_unlock_check = "";
    }
    else {
      $step0_lock_check = "";
      $step0_unlock_check = "checked";      
    }
  }  
  
  $html = <<__HTML;
  <form id="frm_lock" name="frm_lock" action="" method="post">
  <input type=hidden id="step" name="step" value="$step">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>		
			<h1>Lock/Unlock User</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <input type="radio" id="op1" name="op" value="1" $step0_lock_check><label for="op1">Lock User</label>
      <input type="radio" id="op2" name="op" value="2" $step0_unlock_check><label for="op2">Unlock User</label>
      <br>
      <input type="button" id="next" name="next" value="Next" onClick="goStep(1, 0);">
    </div>
  </div>
  </form>
__HTML

  print $html;
}


sub printSelectUserForm {
  my ($html, $cnt, $prompt, @users);
  
  @users = getAvailableUsers($dbh, $op, $user_id);
  $prompt = ($op == 1)? "Select user(s) to lock:" : "Select user(s) to unlock:";
  
  $html = <<__HTML;
  <form id="frm_lock" name="frm_lock" action="" method="post">
  <input type=hidden id="step" name="step" value="$step">
  <input type=hidden id="op" name="op" value="$op">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>		
			<h1>Lock/Unlock User</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <b>$prompt</b>
      <br>
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Username / Alias</b></td><td align=center><b>Current Status</b></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@users) {
    my $this_user_id = $rec->{'user_id'} + 0;
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_user = ($this_alias ne '')? $this_alias : $this_username;
    my $this_status = ($rec->{'status'} eq 'A')? 'Active' : (($rec->{'status'} eq 'D')? 'Locked' : 'Unhappy');
    
    $cnt++;
    $html .= <<__HTML;
    <tr style="background-color:lightyellow">
      <td>
        <input type="checkbox" id="op_user_id_$cnt" name="op_user_id_$cnt" value="$this_user_id">
        <label for="op_user_id_$cnt">$this_user</label>
      </td>
      
      <td align=center>$this_status</td>
    </tr>
__HTML
  }
  
  if (scalar(@users) > 0) {
    $html .= <<__HTML;
      </tbody>
      </table>
      <br>
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr><td colspan=2></td></tr>
      </thead>
      
      <tbody>
      <tr>  
        <td width=50% align=center><input type="button" id="back" name="back" value="Back" onClick="goStep(0, 0);"></td>
        <td width=50% align=center><input type="button" id="next" name="next" value="Save" onClick="goStep(2, $cnt);"></td>
      </tr>
      </tbody>
      </table>
__HTML
  }
  else {
    my $action = ($op == 1)? 'be locked' : 'be unlocked'; 
    $html .= <<__HTML;
        <tr style="background-color:lightyellow"><td colspan=2>No user is available to $action</td></tr>
      </tbody>
      </table>
__HTML
  }
  
  $html .= <<__HTML;
    </div>
  </div>
  </form>  
__HTML
  
  print $html;
}


sub getAvailableUsers {
  my ($dbh, $op, $yourself) = @_;
  my ($sql, $sth, $filter, @result);
  
  $filter = ($op == 1)? "'A'" : "'D', 'U'";
  
  $sql = <<__SQL;
  SELECT user_id, user_name, user_alias, status
    FROM user_list
    WHERE status IN ($filter)
      AND user_id <> ?
    ORDER BY user_alias, user_name
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($yourself)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'user_id' => $data[0], 'username' => $data[1], 'alias' => $data[2], 'status' => $data[3]}
    }
  }
  $sth->finish;
  
  return @result;
}


sub changeStatusForSelectedUsers {
  my ($dbh, $role, $select_users_ref) = @_;
  my ($ok, $msg, $sql, $sth, $status, @select_users);
  
  $ok = 1;
  $msg = '';
  
  $status = ($op == 1)? 'D' : 'A';
  
  @select_users = @$select_users_ref;
  foreach my $this_user_id (@select_users) {
    $sql = <<__SQL;
    UPDATE user_list
      SET status = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($status, $this_user_id)) {
      my $action = ($op == 1)? 'lock' : 'unlock';
      $msg .= "Unable to $action user (id = $this_user_id). Error: " . $sth->errstr . "\n";
      $ok = 0;
    }
    $sth->finish;
    
    #-- If it is user locking operation, delete all session(s) of the locked user. --#
    if ($status eq 'D') {
      $sql = <<__SQL;
      DELETE FROM web_session
        WHERE user_id = ?
__SQL

      $sth = $dbh->prepare($sql);
      $sth->execute($this_user_id);
      $sth->finish;
    }
  }
  
  return ($ok, $msg);
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
    my $brief_msg = "Lock user account failure (lock_user)"; 
    my $detail_msg = "Unable to lock a non-administrative user (user id = $user_id) who try to lock/unlock other user(s), please lock this guy manually ASAP.";
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
    
  $subject = "Someone try to lock/unlock other user(s), check for it.";
  $content = "This guy, $user, who is not system administrator but some how get into user locking/unlocking function at $current_datetime from this IP address $ip_address. His/Her account has been locked. Try to find out what is going on.";
  _informAdminSystemProblem($dbh, $user, $subject, $content);       # Defined on sm_user.pl
}


