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
# Program: /www/pdatools/cgi-pl/user/input_user_data.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-10      DW              With unknown reason, long escaped URI data
#                                               (the applicant token) let jQuery Mobile
#                                               library raise error. So, this program is
#                                               created to work-around this issue.
# V1.0.01       2019-01-14      DW              Handle transient status 'S' of selected applicant
#                                               to ensure correct token must be given, before
#                                               he/she can go to this web page.
# V1.0.02       2019-08-28      DW              As 'Save' button is clicked, then disable it to prevent
#                                               multiple user account records adding.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                      # Both are defined on sm_webenv.pl
our $COOKIE_MSG;
our $PDA_BG_COLOR;

my $apply_id = paramAntiXSS('apply_id') + 0;          # Applicant ID. 
my $user = allTrim(paramAntiXSS('user'));             # Username for the applicant.

printFreeHeader('Create Account');                    # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);
my ($ok, $msg, $name, $email);

($ok, $msg, $name, $email) = loadApplicantInfo($dbh, $apply_id);  

if ($ok) {
  $user = ($user eq '')? suggestUserName($name, $email) : $user;
  
  printJavascriptSection();
  printInputForm($user);
}
else {
  alert($msg);
  redirectTo("/cgi-pl/index.pl");
}

dbclose($dbh);
#-- End Main Section --#


sub loadApplicantInfo {
  my ($dbh, $apply_id) = @_;
  my ($sql, $sth, $ok, $msg, $token, $name, $email, $apply_date, $status);
  
  $ok = 1;
  $msg = $name = $email = '';
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT token, name, email, apply_date, status
      FROM applicant
      WHERE apply_id = ?
        AND status = 'S'
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($apply_id)) {
      ($token, $name, $email, $apply_date, $status) = $sth->fetchrow_array();

      if (allTrim($token) eq '') {
        $msg = "Unable to find your apply record";
        $ok = 0;
      }
      else {
        #-- Correct token has been given, so turn applicant's status from 'S' to 'A' again. --# 
        ($ok, $msg) = setApplicantStatus($dbh, $apply_id, 'A');
      }
    }
    else {
      $msg = "System issue is found, please try again later. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
    
    #-- Check whether approval period has been passed --#
    if ($ok) {
      if (_isTimeLimitPassed($dbh, $apply_date, '7 00:00:00')) {      # Note: 1. '7 00:00:00' means 7 days, 2. It is defined on sm_user.pl
        setApplicantStatus($dbh, $apply_id, 'T');      # Timeout.
        $msg = "You are too late to finalize your registration, valid period has been passed. Please apply again.";
        $ok = 0;
      }      
    }    
  }
  else {
    $msg = "Invalid database connection handler is found, process cannot proceed.";
    $ok = 0;
  }
  
  return ($ok, $msg, $name, $email);  
}


sub suggestUserName {
  my ($name, $email) = @_;
  my ($result, @buffer);
  
  $result = '';
  
  #-- Try email first --#
  @buffer = split('@', $email);
  $result = (scalar(@buffer) > 0)? allTrim($buffer[0]) : '';
  $result =~ s/\.//g;
  $result = allTrim($result);
  
  if ($result eq '') {
    #-- Try applicant's name --#
    $result = lc(allTrim($name));
    $result =~ s/ //g;
  }
  
  if ($result ne '') {
    $result = $result . _generateRandomStr('N', 2);
  }
  else {
    $result = _generateRandomStr('A', 6);
  }
  
  return $result;
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>    
  <script type="text/javascript" src="/js/common_lib.js"></script>
  
  <script type="text/javascript">
    function goCreateUserAccount() {
      if (dataSetValid()) {
        document.getElementById("save").disabled = true;
        document.getElementById("frmAddUser").action = "/cgi-pl/user/create_user_acct.pl";
        document.getElementById("frmAddUser").submit();
      }
    }
    
    function dataSetValid() {
      var user = allTrim(document.getElementById("user").value);
      var alias = allTrim(document.getElementById("alias").value);
      var happy_pw1 = document.getElementById("happy_passwd1").value;
      var happy_pw2 = document.getElementById("happy_passwd2").value;
      var unhappy_pw1 = document.getElementById("unhappy_passwd1").value;
      var unhappy_pw2 = document.getElementById("unhappy_passwd2").value;
      
      if (user == "") {
        alert("User name is compulsory");
        document.getElementById("user").focus();
        return false;
      }
      
      if (alias == "") {
        alert("Alias is compulsory");
        document.getElementById("alias").focus();
        return false;        
      }
      
      if (happy_pw1.length < 8) {
        alert("Happy password must contain 8 characters or more");
        document.getElementById("happy_passwd1").focus();
        return false;
      }
      else {
        if (happy_pw1 != happy_pw2) {
          alert("Happy password is not match");
          document.getElementById("happy_passwd2").focus();
          return false;
        }
      }
      
      if (unhappy_pw1.length < 8) {
        alert("Unhappy password must contain 8 characters or more");
        document.getElementById("unhappy_passwd1").focus();
        return false;
      }
      else {
        if (unhappy_pw1 != unhappy_pw2) {
          alert("Unhappy password is not match");
          document.getElementById("unhappy_passwd2").focus();
          return false;
        }
      }
      
      if (happy_pw1 == unhappy_pw1) {
        alert("Happy password must be different from unhappy password");
        document.getElementById("happy_passwd1").focus();
        return false;        
      }
            
      return true;
    }
  </script>
__JS
}


sub printInputForm {
  my ($user) = @_;
  my ($red_dot, $message, $spaces, $copy_right);
  
  $red_dot = "<font color='red'>*</font>";
  $message = "<font color='darkblue'>Hi $name, you need to input further data to complete your registration.</font><br><br>";
  $spaces = '&nbsp;' x 2; 
  $copy_right = getDecoySiteCopyRight();      # Defined on sm_webenv.pl
    
  print <<__HTML;
  <form id="frmAddUser" name="frmAddUser" action="" method="post" data-ajax="false">
  <input type=hidden id="apply_id" name="apply_id" value="$apply_id">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR"> 
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <h1>Create Account</h1>
    </div>
  
    <div data-role="content" style="ui-content">
      $message
      
      <label for="user"><b>Username $red_dot</b></label>
      <input type=text id="user" name="user" value="$user">

      <label for="alias"><b>Alias $red_dot</b></label>
      <input type=text id="alias" name="alias">
  
      <label for="happy_passwd1"><b>Happy Password $red_dot (2)</b></label>
      <input type=password id="happy_passwd1" name="happy_passwd1">
      (8 chars. or more)

      <label for="happy_passwd2"><b>Retype Happy Password $red_dot</b></label>
      <input type=password id="happy_passwd2" name="happy_passwd2">

      <label for="unhappy_passwd1"><b>Unhappy Password $red_dot (3)</b></label>
      <input type=password id="unhappy_passwd1" name="unhappy_passwd1">
      (8 chars. or more)
  
      <label for="unhappy_passwd2"><b>Retype Unhappy Password $red_dot</b></label>
      <input type=password id="unhappy_passwd2" name="unhappy_passwd2">
      <br>
      <input type=button id="save" name="save" value="Create Account" onClick="goCreateUserAccount();">  
      <br>
      
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td colspan=2><b>Remarks:</b></td> 
        </tr>
      
        <tr>
          <td valign=top>1.$spaces</td>
          <td valign=top>Input items with $red_dot are compulsory that they must be filled</td>
        </tr>
      
        <tr>
          <td valign=top>2.$spaces</td>
          <td valign=top>Happy password means the <font color='darkblue'>normal</font> password you use to login to the system</td>
        </tr>

        <tr>
          <td valign=top>3.$spaces</td>
          <td valign=top>Please <font color='red'>ask</font> your referrer the purpose of the unhappy password and it's usage.</td>
        </tr>
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width="100%" cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr><td align=center><font size="2px">$copy_right</font></td></tr>
      </tbody>
      </table>
    </div>     
  </div>
  </form>
__HTML
}
