#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/admin/demote_user.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-17      AY              Demote user to common user or trusted user. 
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
my $op = paramAntiXSS('op') + 0;                           # 0 = Unknown, 1 = Demote to common user, 2 = Demote to trusted user.
my @demote_users = getDemoteUsers();

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

printJavascriptSection();

if ($step == 0) {
  printSelectOperationForm();  
}
elsif ($step == 1) {
  printSelectUserForm();
}
elsif ($step == 2) {
  my ($ok, $msg) = demoteSelectedUsers($dbh, $op, \@demote_users);
  if ($ok) {
    redirectTo("/cgi-pl/msg/message.pl");
  }
  else {
    alert($msg);
    back();
  }
}

dbclose($dbh);
#-- End Main Section --#


sub getDemoteUsers {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /dm_user_id_/) {
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
        document.getElementById("frm_demote").submit();
      }
      else {
        if (to_step == 2) {
          if (dataSetValid(cnt)) {
            document.getElementById("step").value = to_step;
            document.getElementById("frm_demote").submit();          
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
        if (document.getElementById("dm_user_id_" + ix).checked) {
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
  my ($html, $step0_cu_check, $step0_tu_check);
  
  if ($step == 0) {
    $op = ($op <= 0)? 1 : $op; 
    if ($op == 1) {
      $step0_cu_check = "checked";
      $step0_tu_check = "";
    }
    else {
      $step0_cu_check = "";
      $step0_tu_check = "checked";      
    }
  }  
  
  $html = <<__HTML;
  <form id="frm_demote" name="frm_demote" action="" method="post">
  <input type=hidden id="step" name="step" value="$step">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>		
			<h1>Demote User</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <input type="radio" id="op1" name="op" value="1" $step0_cu_check><label for="op1">To Common User</label>
      <input type="radio" id="op2" name="op" value="2" $step0_tu_check><label for="op2">To Trusted User</label>
      <br>
      <input type="button" id="next" name="next" value="Next" onClick="goStep(1, 0);">
    </div>
  </div>
  </form>
__HTML

  print $html;
}


sub printSelectUserForm {
  my ($html, $cnt, @users);
  
  @users = getAvailableUsers($dbh, $op, $user_id);    # Exclude yourself.
  
  $html = <<__HTML;
  <form id="frm_demote" name="frm_demote" action="" method="post">
  <input type=hidden id="step" name="step" value="$step">
  <input type=hidden id="op" name="op" value="$op">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>		
			<h1>Demote User</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <b>Select user(s) to demote:</b>
      <br>
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Username / Alias</b></td><td align=center><b>Current Role</b></td></tr>
      </thead>
      <tbody>        
__HTML

  $cnt = 0;
  foreach my $rec (@users) {
    my $this_user_id = $rec->{'user_id'} + 0;
    my $this_username = allTrim($rec->{'username'});
    my $this_alias = allTrim($rec->{'alias'});
    my $this_user = ($this_alias ne '')? $this_alias : $this_username;
    my $this_role = ($rec->{'role'} == 0)? 'Common User' : (($rec->{'role'} == 1)? 'Trusted User' : 'System Admin');
    
    if ($this_user_id != $user_id) {      # Don't demote yearself!
      $cnt++;
      $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td>
          <input type="checkbox" id="dm_user_id_$cnt" name="dm_user_id_$cnt" value="$this_user_id">
          <label for="dm_user_id_$cnt">$this_user</label>
        </td>
      
        <td align=center>$this_role</td>
      </tr>
__HTML
    }
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
    my $post = ($op == 1)? 'common user' : 'trusted user'; 
    $html .= <<__HTML;
        <tr style="background-color:lightyellow"><td colspan=2>No user is available to demote to $post</td></tr>
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
  
  $filter = ($op == 1)? "1, 2" : "2";
  
  $sql = <<__SQL;
  SELECT user_id, user_name, user_alias, user_role
    FROM user_list
    WHERE status = 'A'
      AND user_role IN ($filter)
      AND user_id <> ?
    ORDER BY user_alias, user_name
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($yourself)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'user_id' => $data[0], 'username' => $data[1], 'alias' => $data[2], 'role' => $data[3]}
    }
  }
  $sth->finish;
  
  return @result;
}


sub demoteSelectedUsers {
  my ($dbh, $op, $demote_users_ref) = @_;
  my ($ok, $msg, $sql, $sth, $role, @demote_users);
  
  $ok = 1;
  $msg = '';
  $role = $op - 1;
  
  @demote_users = @$demote_users_ref;
  foreach my $this_user_id (@demote_users) {
    $sql = <<__SQL;
    UPDATE user_list
      SET user_role = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($role, $this_user_id)) {
      $msg .= "Unable to demote user (id = $this_user_id). Error: " . $sth->errstr . "\n";
      $ok = 0;
    }    
  }
  
  return ($ok, $msg);
}
