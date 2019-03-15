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
# Program: /www/itnews/cgi-pl/user/create_msg_user.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-10      AY              Create user of the messaging system (As
#                                               connection_mode is 1 or 3 on system settings).
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use Authen::Passphrase::BlowfishCrypt;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $name = allTrim(paramAntiXSS('name'));                  # Name of the new user 
my $user = allTrim(paramAntiXSS('user'));                  # Login username
my $alias = allTrim(paramAntiXSS('alias'));                # Alias of the new user
my $email = allTrim(paramAntiXSS('email'));                # Email address of the new user
my $happy_passwd = paramAntiXSS('happy_passwd1');          # Happy password in plain text
my $unhappy_passwd = paramAntiXSS('unhappy_passwd1');      # Unhappy password in plain text

my $dbh = dbconnect($COOKIE_MSG);
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $user_role = getUserRole($dbh, $user_id);               # Defined on sm_user.pl
my $ok;
my $msg;

printJavascriptSection();

if ($user_role >= 1) {         # Only trusted users or system administrators are allowed.
  if ($oper_mode eq 'S') {
    $ok = 1;
    $msg = '';
    
    if (userExist($dbh, $user)) {
      $msg = "User name <$user> has already existed.";
      $ok = 0;    
    }
  
    if (aliasExist($dbh, $alias)) {
      $msg = "Alias <$alias> has already existed.";
      $ok = 0;
    }
    
    if ($ok) {
      #-- Note: Assume the current user is the referrer of the newly created user --#
      ($ok, $msg) = createUserAccount($dbh, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $user_id);
    }
  
    if ($ok) {
      alert("User $user is created successfully.");
      redirectTo("/cgi-pl/user/create_msg_user.pl");
    }
    else {
      alert($msg);
      retryIt();
    }
  }
  else {    
    printCreateUserForm();  
  }
}
else {
  if ($user_id > 0) {  
    #-- Something is wrong, the system may be infiltrated by hacker.   --#
    #-- Note: if $user_id <= 0, it is highly possible the user in this --#
    #-- page has been timeout.                                         --#
    lockUserAcct($dbh, $user_id);
  }
  #-- Expel the suspicious user --#
  redirectTo("/cgi-pl/auth/logout.pl");
}

dbclose($dbh);
#-- End Main Section --#


sub userExist {
  my ($dbh, $user) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM user_list
    WHERE user_name = ?
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user)) {
    ($cnt) = $sth->fetchrow_array();
    ($result) = ($cnt > 0)? 1 : 0;    
  }
  else {
    $result = 1;
  }
  $sth->finish;
  
  return $result;
}


sub aliasExist {
  my ($dbh, $alias) = @_;  
  my ($sql, $sth, $cnt, $result);
  
  if ($alias ne '') {
    $sql = <<__SQL;
    SELECT COUNT(*) AS cnt
      FROM user_list
      WHERE user_alias = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($alias)) {
      ($cnt) = $sth->fetchrow_array();
      ($result) = ($cnt > 0)? 1 : 0;    
    }
    else {
      $result = 1;
    }
    $sth->finish;
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub createUserAccount {
  my ($dbh, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $referrer_id) = @_;
  my ($ok, $msg, $sql, $sth, $crypted_happy_passwd, $crypted_unhappy_passwd, $ppr);
  
  $ok = 1;
  $msg = '';  

  $ppr = Authen::Passphrase::BlowfishCrypt->new(cost => 15, salt_random => 1, passphrase => $happy_passwd);
  $crypted_happy_passwd = $ppr->as_crypt;
  $ppr = Authen::Passphrase::BlowfishCrypt->new(cost => 15, salt_random => 1, passphrase => $unhappy_passwd);
  $crypted_unhappy_passwd = $ppr->as_crypt;
  
  $sql = <<__SQL;
  INSERT INTO user_list
  (user_name, user_alias, name, happy_passwd, unhappy_passwd, login_failed_cnt, user_role, email, refer_by, join_date, status, cracked, inform_new_msg)
  VALUES
  (?, ?, ?, ?, ?, 0, 0, ?, ?, CURRENT_TIMESTAMP(), 'A', 0, 1)
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user, $alias, $name, $crypted_happy_passwd, $crypted_unhappy_passwd, $email, $referrer_id)) {
    $msg = "Unable to add user account. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub retryIt {
  my ($url);
  
  $url = "/cgi-pl/user/create_msg_user.pl?name=$name&user=$user&alias=$alias&email=$email";
  redirectTo($url);  
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    function goCreateUserAccount() {
      if (dataSetValid()) {
        \$('#oper_mode').val("S");
        \$('#frm_add_user').submit();
      }
    }
    
    function dataSetValid() {
      var name = allTrim(\$('#name').val());
      var user = allTrim(\$("#user").val());
      var alias = allTrim(\$("#alias").val());
      var happy_pw1 = \$("#happy_passwd1").val();
      var happy_pw2 = \$("#happy_passwd2").val();
      var unhappy_pw1 = \$("#unhappy_passwd1").val();
      var unhappy_pw2 = \$("#unhappy_passwd2").val();

      if (name == "") {
        alert("User's name is compulsory");
        \$('#name').focus();
        return false;
      }

      if (user == "") {
        alert("Login username is compulsory");
        \$('#user').focus();
        return false;
      }
      
      if (alias == "") {
        alert("Alias is compulsory");
        \$('#alias').focus();
        return false;        
      }
      
      if (happy_pw1.length < 8) {
        alert("Happy password must contain 8 characters or more");
        \$('#happy_passwd1').focus();
        return false;
      }
      else {
        if (happy_pw1 != happy_pw2) {
          alert("Happy password is not match");
          \$('#happy_passwd2').focus();
          return false;
        }
      }
      
      if (unhappy_pw1.length < 8) {
        alert("Unhappy password must contain 8 characters or more");
        \$('#unhappy_passwd1').focus();
        return false;
      }
      else {
        if (unhappy_pw1 != unhappy_pw2) {
          alert("Unhappy password is not match");
          \$('#unhappy_passwd2').focus();
          return false;
        }
      }
      
      if (happy_pw1 == unhappy_pw1) {
        alert("Happy password must be different from unhappy password");
        \$('#happy_passwd1').focus();
        return false;        
      }
            
      return true;
    }
  </script>
__JS
}


sub printCreateUserForm {
  my ($html, $red_dot);
  
  $red_dot = "<font color='red'>*</font>";
  
  $html = <<__HTML;
  <form id="frm_add_user" name="frm_add_user" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">  
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/msg/message.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Create User</h1>
    </div>
    
    <div data-role="main" class="ui-body-d ui-content">
      <label for="name">User's name $red_dot:</label>
      <input type=text id="name" name="name" value="$name" maxlength=256>
      <label for="user">Login username $red_dot:</label>
      <input type=text id="user" name="user" value="$user" maxlength=64>
      <label for="alias">Alias $red_dot:</label>
      <input type=text id="alias" name="alias" value="$alias" maxlength=256>
      <label for="email">Email address:</label>
      <input type=text id="email" name="email" value="$email" maxlength=256>
      Happy password (input twice) $red_dot:   
      <div data-role="controlgroup">
        <input type=password id="happy_passwd1" name="happy_passwd1" value="" maxlength=256>
        <input type=password id="happy_passwd2" name="happy_passwd2" value="" maxlength=256>
      </div>      
      Unhappy password (input twice) $red_dot:
      <div data-role="controlgroup">
        <input type=password id="unhappy_passwd1" name="unhappy_passwd1" value="" maxlength=256>
        <input type=password id="unhappy_passwd2" name="unhappy_passwd2" value="" maxlength=256>
      </div>
      <br>
      <input type=button id="save" name="save" value="Create" data-icon="plus" onClick="goCreateUserAccount();">
      <br>
      <b>Remarks:</b><br>
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td valign=top>1.&nbsp;</td>
          <td valign=top>Input items with $red_dot are compulsory that they must be filled.</td>
        </tr>
        <tr>
          <td valign=top>2.&nbsp;</td>
          <td valign=top>Please give user's email address (if you know it) even it is not a compulsory data.</td>
        </tr>
      </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML
  
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
    my $brief_msg = "Lock user account failure (create user account manually)"; 
    my $detail_msg = "Unable to lock a common user (user id = $user_id) who try to create new user account, please lock this guy manually ASAP.";
    _logSystemError($dbh, $user_id, $detail_msg, $brief_msg);
  }
  $sth->finish;
}
