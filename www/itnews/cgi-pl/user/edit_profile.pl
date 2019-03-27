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
# Program: /www/itnews/cgi-pl/user/edit_profile.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-19      DW              User profile maintenance.
# V1.0.01       2018-08-10      DW              Remove usage 'crypt' to encrypt user passwords
#                                               due to it's serious limitation (only first 8
#                                               characters are used for encrypted password).
# V1.0.02       2018-08-23      DW              Add Telegram ID maintenance.
# V1.0.03       2018-09-21      DW              Use new encryption method to protect user passwords. 
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

my $op = paramAntiXSS('op') + 0;                           # 1 = Alias, 2 = Email, 3 = Happy passord, 4 = Unhappy pasword, 5 = Telegram chat ID.
my $oper_mode = allTrim(paramAntiXSS('oper_mode'));        # 'S' = Save, others go to data input form.
my $alias = allTrim(paramAntiXSS('alias'));
my $email = allTrim(paramAntiXSS('email'));
my $tg_id = allTrim(paramAntiXSS('tg_id'));
my $happy_passwd = allTrim(paramAntiXSS('happy_passwd'));
my $unhappy_passwd = allTrim(paramAntiXSS('unhappy_passwd'));

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my %user_profile = getUserProfile($dbh, $user_id);

printJavascriptSection();

if ($oper_mode eq 'S') {
  my ($ok, $msg) = (1, '');
  
  if ($op == 1) {
    if (aliasIsExist($dbh, $user_id, $alias)) {
      $msg = "Alias <$alias> has already existed. Please use another alias.";
      $ok = 0;
    } 
  }
  
  if ($op == 3) {
    if (newHappyPasswdEqualToUnhappyPasswd($dbh, $user_id, $happy_passwd)) {
      $msg = "Happy password must not equal to unhappy password.";
      $ok = 0;
    }    
  }
  
  if ($op == 4) {
    if (newUnhappyPasswdEqualToHappyPasswd($dbh, $user_id, $unhappy_passwd)) {
      $msg = "Unhappy password must not equal to happy password.";
      $ok = 0;
    }        
  }
  
  if ($ok) {
    ($ok, $msg) = updateProfile($dbh, $op, $user_id, $alias, $email, $tg_id, $happy_passwd, $unhappy_passwd);  
  }
  
  if ($ok) {
    redirectTo("/cgi-pl/msg/message.pl");
  }
  else {
    alert($msg);
    redirectTo("/cgi-pl/user/edit_profile.pl?op=$op");
  }  
}
else {
  printDataInputForm($op);
}

dbclose($dbh);
#-- End Main Section --#


sub getUserProfile {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, @data, %result);
  
  %result = ();
  
  $sql = <<__SQL;
  SELECT user_alias, email, tg_id
    FROM user_list
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    @data = $sth->fetchrow_array();
    %result = ('alias' => $data[0], 'email' => $data[1], 'tg_id' => $data[2]);
  }
  $sth->finish;
  
  return %result;
}


sub aliasIsExist {
  my ($dbh, $user_id, $alias) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $result = 1;

  if (allTrim($alias) ne '') {    
    $sql = <<__SQL;
    SELECT COUNT(*) AS cnt
      FROM user_list
      WHERE user_alias = ?
        AND user_id <> ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($alias, $user_id)) {
      ($cnt) = $sth->fetchrow_array();
      $result = ($cnt > 0)? 1 : 0;      
    }
    $sth->finish;
  }
  else {
    #-- All blank alias will be ignored, and considered as non-existed. --#
    $result = 0;
  }
  
  return $result;
}


sub newHappyPasswdEqualToUnhappyPasswd {
  my ($dbh, $user_id, $happy_passwd) = @_;
  my ($sql, $sth, $unhappy_passwd, $ppr, $result);
  
  $sql = <<__SQL;
  SELECT unhappy_passwd
    FROM user_list
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($unhappy_passwd) = $sth->fetchrow_array();
    $unhappy_passwd = allTrim($unhappy_passwd);
  }
  $sth->finish;
  
  $ppr = Authen::Passphrase->from_crypt($unhappy_passwd); 
  $result = ($ppr->match($happy_passwd))? 1 : 0;
  
  return $result;
}


sub newUnhappyPasswdEqualToHappyPasswd {
  my ($dbh, $user_id, $unhappy_passwd) = @_;
  my ($sql, $sth, $happy_passwd, $ppr, $result);
  
  $sql = <<__SQL;
  SELECT happy_passwd
    FROM user_list
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    ($happy_passwd) = $sth->fetchrow_array();
    $happy_passwd = allTrim($happy_passwd);
  }
  $sth->finish;

  $ppr = Authen::Passphrase->from_crypt($happy_passwd); 
  $result = ($ppr->match($unhappy_passwd))? 1 : 0;
  
  return $result;  
}


sub updateProfile {
  my ($dbh, $op, $user_id, $alias, $email, $tg_id, $happy_passwd, $unhappy_passwd) = @_;
  my ($ok, $msg, $sql, $sth, $ppr, $crypted_passwd);

  $ok = 1;
  $msg = '';
  
  if ($op == 1) {
    $sql = <<__SQL;
    UPDATE user_list
      SET user_alias = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($alias, $user_id)) {
      $msg = "Unable to update alias. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;    
  }
  elsif ($op == 2) {
    $sql = <<__SQL;
    UPDATE user_list
      SET email = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($email, $user_id)) {
      $msg = "Unable to update email. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;        
  }
  elsif ($op == 3) {
    $ppr = Authen::Passphrase::BlowfishCrypt->new(cost => 15, salt_random => 1, passphrase => $happy_passwd);
    $crypted_passwd = $ppr->as_crypt;
    
    $sql = <<__SQL;
    UPDATE user_list
      SET happy_passwd = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($crypted_passwd, $user_id)) {
      $msg = "Unable to update happy password. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;            
  }
  elsif ($op == 4) {
    $ppr = Authen::Passphrase::BlowfishCrypt->new(cost => 15, salt_random => 1, passphrase => $unhappy_passwd);
    $crypted_passwd = $ppr->as_crypt;    
    
    $sql = <<__SQL;
    UPDATE user_list
      SET unhappy_passwd = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($crypted_passwd, $user_id)) {
      $msg = "Unable to update unhappy password. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;                
  }
  elsif ($op == 5) {
    $sql = <<__SQL;
    UPDATE user_list
      SET tg_id = ?
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($tg_id, $user_id)) {
      $msg = "Unable to update Telegram ID. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;            
  }
  
  if (!$ok) {
    my $err_dtl = "$msg --> SQL: $sql";
    _logSystemError($dbh, $user_id, $err_dtl, 'User profile update failure');        # Defined on sm_user.pl
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
    function saveAlias() {
      document.getElementById("oper_mode").value = 'S';
      document.getElementById("frmEditProfile").submit();
    }
    
    function saveEmail() {
      var this_email = allTrim(document.getElementById("email").value);        // Defined on common_lib.js
      if (this_email == "") {
        alert("Email is a compulsory data which must be given");
        document.getElementById("email").focus();
      }
      else {
        document.getElementById("oper_mode").value = 'S';
        document.getElementById("frmEditProfile").submit();        
      }
    }
    
    function saveHappyPasswd() {
      var this_passwd = allTrim(document.getElementById("happy_passwd").value);
      var this_passwd_rt = allTrim(document.getElementById("happy_passwd_rt").value);
      
      if (this_passwd.length < 8) {
        alert("Password length is too short");
        document.getElementById("happy_passwd").focus();
        return false;
      }
      
      if (this_passwd != this_passwd_rt) {
        alert("New happy password is not match, try again");
        document.getElementById("happy_passwd").focus();
        return false;
      }
      else {
        document.getElementById("oper_mode").value = 'S';
        document.getElementById("frmEditProfile").submit();                
      }      
    }
    
    function saveUnhappyPasswd() {
      var this_passwd = allTrim(document.getElementById("unhappy_passwd").value);
      var this_passwd_rt = allTrim(document.getElementById("unhappy_passwd_rt").value);
      
      if (this_passwd.length < 8) {
        alert("Password length is too short");
        document.getElementById("unhappy_passwd").focus();
        return false;
      }
      
      if (this_passwd != this_passwd_rt) {
        alert("New unhappy password is not match, try again");
        document.getElementById("unhappy_passwd").focus();
        return false;
      }
      else {
        document.getElementById("oper_mode").value = 'S';
        document.getElementById("frmEditProfile").submit();                
      }            
    }
    
    function saveTelegramID() {
      var this_tg_id = allTrim(document.getElementById("tg_id").value);
      var ok = 1;
      
      if (this_tg_id != "") {
        if (isNaN(this_tg_id)) {
          alert("Telegram ID is a numeric data.");
          document.getElementById("tg_id").focus();
          ok = 0;
        }
      }

      if (ok) {
        document.getElementById("oper_mode").value = 'S';
        document.getElementById("frmEditProfile").submit();        
      }      
    }
  </script>  
__JS
}


sub printDataInputForm {
  my ($op) = @_;
  my ($html);
  
  $html = <<__HTML;
  <form id="frmEditProfile" name="frmEditProfile" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">    
  
  <div data-role="page" id="config_page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="/cgi-pl/msg/message.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>		
			<h1>Setup</h1>
    </div>
    
    <div data-role="main" class="ui-content">
__HTML
  
  if ($op == 1) {     # Alias
    $html .= <<__HTML;
    <label for="alias">Alias:</label>
    <input type="text" id="alias" name="alias" value="$user_profile{'alias'}" maxlength=64>
    <br>
    <a href="#" data-role="button" id="save" onClick="saveAlias();">Save</a>
__HTML
  }
  elsif ($op == 2) {  # Email
    $html .= <<__HTML;
    <label for="email">Email:</label>
    <input type="email" id="email" name="email" value="$user_profile{'email'}" maxlength=256>
    <br>
    <a href="#" data-role="button" id="save" onClick="saveEmail();">Save</a>
__HTML
  }
  elsif ($op == 3) {  # Happy password
    $html .= <<__HTML;
    <label for="happy_passwd">New Happy Password (8 characters or more):</label>
    <input type="password" id="happy_passwd" name="happy_passwd" maxlength=256>
    <label for="happy_passwd_rt">Retype New Happy Password:</label>
    <input type="password" id="happy_passwd_rt" name="happy_passwd_rt" maxlength=256>    
    <br>
    <a href="#" data-role="button" id="save" onClick="saveHappyPasswd();">Save</a>
__HTML
  }
  elsif ($op == 4) {  # Unhappy password
    $html .= <<__HTML;
    <label for="unhappy_passwd">New Unappy Password (8 characters or more):</label>
    <input type="password" id="unhappy_passwd" name="unhappy_passwd" maxlength=256>
    <label for="unhappy_passwd_rt">Retype New Unhappy Password:</label>
    <input type="password" id="unhappy_passwd_rt" name="unhappy_passwd_rt" maxlength=256>    
    <br>
    <a href="#" data-role="button" id="save" onClick="saveUnhappyPasswd();">Save</a>
__HTML
  }
  elsif ($op == 5) {  # Telegram ID
    my %tg_bot_profile = getTelegramBotProfile($dbh);                   # Defined on sm_webenv.pl
    my $has_tg_bot = ($tg_bot_profile{'bot_username'} ne '')? 1 : 0;
    my $bot_add_html = '';
    my $get_tg_id_html = ''; 
    
    if ($has_tg_bot) {
      my $bot_link = "https://t.me/$tg_bot_profile{'bot_username'}";
      
      $bot_add_html = <<__HTML;
      <b>Step 1: Add SMS notification bot to your Telegram app.</b>
      <br>
      Click 'Add SMS notification bot' => Click Send Message => Click Start
      <br>
      <a href="$bot_link">Add SMS notification bot</a>
      <br>
      <br>
__HTML
    }
    else {
      $bot_add_html = <<__HTML;
      It seems that Telegram notification bot doesn't exist,
      please go to next step directly. However, Telegram notification
      is not possible as notification bot doesn't exist. Please report
      this issue to system administrator.
      <br>
      <br>
__HTML
    }
    
    $get_tg_id_html = <<__HTML;
    <b>Step 2: Get and input your Telegram ID.</b>
    <br>
    Click 'Check my Telegram ID' => Click Send Message => Click Start to get
    your Telegram ID, then input your Telegram ID to the field below, and save it.
    <br>
    <a href="https://t.me/my_id_bot">Check my Telegram ID</a>
    <br>
    <br>
__HTML
    
    $html .= <<__HTML;
    Here is setup for the system to notify you new message via Telegram.
    <br><br>
    
    $bot_add_html
    
    $get_tg_id_html
    
    <label for="tg_id">Telegram ID:</label>
    <input type="text" id="tg_id" name="tg_id" value="$user_profile{'tg_id'}" maxlength=128>
    <br>
    <a href="#" data-role="button" id="save" onClick="saveTelegramID();">Save</a>
__HTML
  }  
  else {
    $html .= <<__HTML;
    <a href="/cgi-pl/msg/message.pl" data-role="button" id="back" name="back">Invalid profile amendment option <br>is given, click me to return.</a>
__HTML
  }
  
  $html .= <<__HTML;
    </div>
  </div>
  </form>  
__HTML
  
  print $html;
}


