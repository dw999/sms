#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/admin/system_setup.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-09-28      AY              Entire system parameters setup main menu
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $ip_address = allTrim($user_info{'IP_ADDRESS'});

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {
  printSystemSetupMenu();
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


sub isHeSysAdmin {
  my ($dbh, $user_id) = @_;
  my ($role, $result);
  
  $role = getUserRole($dbh, $user_id);               # Defined on sm_user.pl
  $result = ($role == 2)? 1 : 0;
  
  return $result;
}


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>

  <script>
    function goBack() {
      window.location.href = "/cgi-pl/msg/message.pl";
    }
  </script>
__JS
}


sub printSystemSetupMenu {
  my ($html, $warning);

  $warning = <<__HTML;
  <font color="red"><b>Warning:</b><br>Incorrect settings change may cause system malfunction and data lost!</font> 
__HTML
  
  $html = <<__HTML;
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>System Settings</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <a href="/cgi-pl/admin/maintain_main_sites.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">Main Sites</a>
      <a href="/cgi-pl/admin/maintain_email_senders.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">Email Senders</a>      
      <a href="/cgi-pl/admin/maintain_decoy_sites.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">Decoy Sites</a>
      <a href="/cgi-pl/admin/maintain_file_types.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">File Types</a>
      <a href="/cgi-pl/admin/maintain_sys_settings.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">Misc. System Settings</a>
      <a href="/cgi-pl/admin/telegram_bot_maintain.pl" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">Telegram Bot</a>
      <br>
      $warning      
    </div>
  </div>
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
    my $brief_msg = "Lock user account failure (system_setup)"; 
    my $detail_msg = "Unable to lock a non-administrative user (user id = $user_id) who try to amend system settings, please lock this guy manually ASAP.";
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
    
  $subject = "Someone try to amend system settings, check for it.";
  $content = "This guy, $user, who is not system administrator but some how get into system parameters setup function at $current_datetime from this IP address $ip_address. His/Her account has been locked. Try to find out what is going on.";
  _informAdminSystemProblem($dbh, $user, $subject, $content);       # Defined on sm_user.pl
}
