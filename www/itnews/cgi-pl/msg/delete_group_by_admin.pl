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
# Program: /www/itnews/cgi-pl/msg/delete_group_by_admin.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-15      DW              Remove selected messaging group(s) by system
#                                               administrator.
# V1.0.01       2019-10-12      DW              Fix a security loophole by checking whether current
#                                               user is system administrator.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));
my @delete_groups = getGroupsToBeDeleted();

my $dbh = dbconnect($COOKIE_MSG);                          # Function 'getGroupMembers' need database connection, so it is put in here.

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $ip_address = allTrim($user_info{'IP_ADDRESS'});

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($oper_mode eq 'S') {
    my ($ok, $msg) = deleteSelectedGroups($dbh, \@delete_groups);      

    if ($ok) {
      redirectTo("/cgi-pl/msg/message.pl");
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    printJavascriptSection();
    printSelectGroupToDeleteForm();
  }
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
#-- End Main Section --#


sub getGroupsToBeDeleted {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /group_id_/) {
      my $this_group_id = $params{$this_key} + 0;
      if ($this_group_id > 0) {
        push @result, $this_group_id;
      }
    }    
  }
  
  return @result;  
}


sub deleteSelectedGroups {
  my ($dbh, $delete_groups_ref) = @_;
  my ($ok, $msg, @delete_groups);
  
  $ok = 1;
  $msg = '';
  
  @delete_groups = @$delete_groups_ref;
  foreach my $this_group_id (@delete_groups) {
    ($ok, $msg) = deleteMessageGroup($dbh, $this_group_id);      # Defined on sm_msglib.pl
    if (!$ok) {
      $msg .= $msg;
    }
  }
  
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
    function deleteGroups(cnt) {
      var select_cnt = 0;
    
      for (idx = 1; idx <= cnt; idx++) {
        if (document.getElementById("group_id_" + idx).checked) {
          select_cnt++;
        }
      }
      
      if (select_cnt == 0) {
        alert("You must select at least one message group to proceed");
        return false;
      }
      else {
        var question = '';
        
        if (select_cnt == 1) {
          question = "Are you sure to delete selected message group?";
        }
        else {
          question = "Are you sure to delete selected message groups?";
        }
        
        if (confirm(question)) {
          document.getElementById("oper_mode").value = "S";
          document.getElementById("frm_delete_group").submit();
        }
      }      
    }    
  </script>
__JS
}


sub printSelectGroupToDeleteForm {
  my ($html, $cnt, @groups);
  
  @groups = getAllMessageGroups($dbh, $user_id);          # Defined on sm_msglib.pl
  
  $html = <<__HTML;
  <form id="frm_delete_group" name="frm_delete_group" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>		
			<h1>Delete Group</h1>
    </div>
  
    <div data-role="main" class="ui-content">
      <b>Select group(s) to delete:</b>
      <br>
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr><td></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@groups) {
    my $this_group_id = $rec->{'group_id'} + 0;
    my $this_group_name = allTrim($rec->{'group_name'});

    $cnt++;
    $html .= <<__HTML;
    <tr style="background-color:lightyellow">
      <td>
        <input type="checkbox" id="group_id_$cnt" name="group_id_$cnt" value="$this_group_id"><label for="group_id_$cnt">$this_group_name (id: $this_group_id)</label>
      </td>
    </tr>
__HTML
  }

  if ($cnt > 0) {
    $html .= <<__HTML;
        </tbody>  
        </table>
      </div>  
      
      <div data-role="footer" data-position="fixed">
        <table width=100% cellpadding=1 cellspacing=1>
        <thead>
          <tr><td></td></tr>
        </thead>
        <tbody>        
          <tr><td align=center><input type="button" id="save" name="save" value="Delete" onClick="deleteGroups($cnt);"></td></tr>
        </tbody>  
      </div>  
    </div>
__HTML
  }
  else {
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td>No message group is available to be deleted</td>
        </tr>
        </tbody>  
        </table>
      </div>  
    </div>
__HTML
  }

  print $html;
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
    my $brief_msg = "Lock user account failure (delete_group_by_admin)"; 
    my $detail_msg = "Unable to lock a non-administrative user (user id = $user_id) who try to delete message group(s), please lock this guy manually ASAP.";
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
    
  $subject = "Someone try to delete message group(s), check for it.";
  $content = "This guy, $user, who is not system administrator but some how get into delete message groups function at $current_datetime from this IP address $ip_address. His/Her account has been locked. Try to find out what is going on.";
  _informAdminSystemProblem($dbh, $user, $subject, $content);       # Defined on sm_user.pl
}

