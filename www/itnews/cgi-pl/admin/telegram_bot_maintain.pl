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
# Program: /www/itnews/cgi-pl/admin/telegram_bot_maintain.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-08-23      DW              Telegram bot profile maintenance.
# V1.0.01       2019-10-12      DW              Function 'isHeSysAdmin' is moved to sm_user.pl   
# V1.0.02       2020-01-13      DW              Fix a minor issue on label.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));        # S = Save, others show data input screen.
my $bot_name = allTrim(paramAntiXSS('bot_name'));          # Telegram bot name.
my $bot_username = allTrim(paramAntiXSS('bot_username'));  # Telegram bot username.
my $http_api_token = allTrim(paramAntiXSS('http_api_token'));  # Telegram bot HTTP API token.

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my %tg_bot_profile;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($oper_mode eq 'S') {
    my ($ok, $msg) = saveTelegramBotProfile($dbh, $bot_name, $bot_username, $http_api_token);
    if ($ok) {
      redirectTo("/cgi-pl/msg/message.pl");
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    %tg_bot_profile = getTelegramBotProfile($dbh);
    printDataInputForm();
  }
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. --#
  redirectTo("/cgi-pl/admin/system_setup.pl");    
}

dbclose($dbh);
#-- End Main Section --#


sub saveTelegramBotProfile {
  my ($dbh, $bot_name, $bot_username, $http_api_token) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = deleteBotProfile($dbh);
    
    if ($ok) {
      ($ok, $msg) = addBotProfile($dbh, $bot_name, $bot_username, $http_api_token);
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh); 
    }    
  }
  else {
    $msg = "Unable to start SQL transaction session, process is aborted.";
    $ok = 0;    
  }
  
  return ($ok, $msg);
}


sub deleteBotProfile {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM tg_bot_profile
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove old Telegram bot profile. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub addBotProfile {
  my ($dbh, $bot_name, $bot_username, $http_api_token) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO tg_bot_profile
  (bot_name, bot_username, http_api_token)
  VALUES
  (?, ?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($bot_name, $bot_username, $http_api_token)) {
    $msg = "Unable to create Telegram bot profile. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getTelegramBotProfile {
  my ($dbh) = @_;
  my ($sql, $sth, @data, %result);
  
  $sql = <<__SQL;
  SELECT bot_name, bot_username, http_api_token
    FROM tg_bot_profile
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    @data = $sth->fetchrow_array();
    %result = ('bot_name' => $data[0], 'bot_username' => $data[1], 'http_api_token' => $data[2]);
  }
  $sth->finish;
  
  return %result;
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>    

  <script>
    function saveTgBotProfile() {
      if (dataSetOk()) {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frmTgBot").submit();
      }
    }
    
    function dataSetOk() {
      var bot_name = allTrim(document.getElementById("bot_name").value);
      var bot_username = allTrim(document.getElementById("bot_username").value);
      var api_token = allTrim(document.getElementById("http_api_token").value);
      
      if (bot_name == "" && bot_username == "" && api_token == "") {
        return true;
      }
      
      if (bot_name != "" && bot_username != "" && api_token != "") {
        return true;
      }
      
      if (bot_name == "") {
        alert("Telegram bot name is missing, please give it before saving.");
        document.getElementById("bot_name").focus();
        return false;        
      }
      else if (bot_username == "") {
        alert("Telegram bot username is missing, please give it before saving.");
        document.getElementById("bot_username").focus();
        return false;        
      }      
      else if (api_token == "") {
        alert("HTTP API token is missing, please give it before saving.");
        document.getElementById("http_api_token").focus();
        return false;
      }
      else {
        alert("System issue is found, process cannot proceed.");
        return false;  
      }      
    }
    
    function goBack() {
      window.location.href = "/cgi-pl/admin/system_setup.pl";
    }
    
    function goHome() {
      window.location.href = "/cgi-pl/msg/message.pl"; 
    }    
  </script>
__JS
}

sub printDataInputForm {
  my ($html);

  $html = <<__HTML;  
  <form id="frmTgBot" name="frmTgBot" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page">
    <div data-role="header" style="overflow:hidden;" data-position="fixed">  
			<a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>		
			<h1>Telegram Bot</h1>
      <a href="javascript:goHome();" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>
    </div>
    
    <div data-role="main" class="ui-content">
      <label for="bot_name">Telegram bot name:</label>
      <input type="text" id="bot_name" name="bot_name" value="$tg_bot_profile{'bot_name'}">
      <label for="bot_username">Bot username:</label>      
      <input type="text" id="bot_username" name="bot_username" value="$tg_bot_profile{'bot_username'}">
      <label for="http_api_token">HTTP API Token:</label>      
      <input type="text" id="http_api_token" name="http_api_token" value="$tg_bot_profile{'http_api_token'}">      
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveTgBotProfile();">
      <br>
      <b>Remark:</b>
      <br>
      If you don't know how to create a Telegram bot, please refer to this link: &nbsp;
      <br>
      <a href="https://core.telegram.org/bots">Bots: An introduction for developers</a>
    </div>
  </div>  
  </form>
__HTML
  
  print $html;
}
