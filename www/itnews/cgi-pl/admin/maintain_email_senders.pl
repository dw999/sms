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
# Program: /www/itnews/cgi-pl/admin/maintain_email_senders.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-03      DW              Maintain a list of Gmail addresses which are used
#                                               to send login link and notification to users.
# V1.0.01       2019-10-12      DW              Function 'isHeSysAdmin' is moved to sm_user.pl
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
my $ms_id = paramAntiXSS('ms_id') + 0;                     # ID of mail sender
my $email = paramAntiXSS('email');                         # Email sender address
my $m_user = paramAntiXSS('m_user');                       # Username of email
my $m_pass = paramAntiXSS('m_pass');                       # Password of email
my $smtp_server = paramAntiXSS('smtp_server');             # SMTP server of the email 
my $port = paramAntiXSS('port') + 0;                       # Port number used by the SMTP server

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @ms_list = ();
my %email_sender;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($op eq 'A') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = addNewEmailSender($dbh, $email, $m_user, $m_pass, $smtp_server, $port);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_email_senders.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_email_senders.pl?op=A");
      }        
    }
    else {
      printNewEmailSenderForm();
    }
  }
  elsif ($op eq 'E') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = modifyEmailSender($dbh, $ms_id, $email, $m_user, $m_pass, $smtp_server, $port);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_email_senders.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_email_senders.pl?op=E");
      }        
    }
    else {
      %email_sender = getEmailSenderDetails($dbh, $ms_id);
      printEmailSenderEditForm(\%email_sender);
    }  
  }
  elsif ($op eq 'D') {
    my ($ok, $msg) = deleteEmailSender($dbh, $ms_id);
    if (!$ok) {
      alert($msg);
    }  
    redirectTo("/cgi-pl/admin/maintain_email_senders.pl");
  }
  else {
    @ms_list = getEmailSenderList($dbh);
    printEmailSenderList(\@ms_list); 
  }
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. Expel the suspicious user. --#
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
    
    function addEmailSender() {
      document.getElementById("op").value = "A";
      document.getElementById("frm_email_sender").submit();          
    }
    
    function editEmailSender(ms_id) {
      document.getElementById("op").value = "E";
      document.getElementById("ms_id").value = ms_id;
      document.getElementById("frm_email_sender").submit();      
    }
    
    function deleteEmailSender(ms_id) {
      if (confirm("Are you sure to delete this email sender?")) {
        document.getElementById("op").value = "D";
        document.getElementById("ms_id").value = ms_id;
        document.getElementById("frm_email_sender").submit();
      }
    }
    
    function saveEmailSender() {
      var email = allTrim(\$('#email').val());
      var m_user = allTrim(\$('#m_user').val());
      var m_pass = allTrim(\$('#m_pass').val());
      var smtp_server = allTrim(\$('#smtp_server').val());
      var port = parseInt(\$('#port').val(), 10);
      
      if (email == "") {
        alert("Please input email sender address before saving");
        \$('#email').focus();
        return false;
      }
      
      if (m_user == "") {
        alert("Please input login username for the email sender before saving");
        \$('#m_user').focus();
        return false;
      }
      
      if (m_pass == "") {
        alert("Please input login password for the email sender before saving");
        \$('#m_pass').focus();
        return false;
      }
      
      if (smtp_server == "") {
        alert("Please input SMTP server for the email sender before saving");
        \$('#smtp_server').focus();
        return false;
      }
      
      if (port <= 0 || isNaN(port)) {
        alert("Please input port number used by the SMTP server for the email sender before saving");
        \$('#port').focus();
        return false;
      }
      
      \$('#oper_mode').val("S");
      \$('#frm_email_sender').submit();      
    }
  </script>
__JS
}


sub addNewEmailSender {
  my ($dbh, $email, $m_user, $m_pass, $smtp_server, $port) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO sys_email_sender
  (email, m_user, m_pass, smtp_server, port, status)
  VALUES
  (?, ?, ?, ?, ?, 'A')
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($email, $m_user, $m_pass, $smtp_server, $port)) {
    $msg = "Unable to add email sender $email. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
    
  return ($ok, $msg);
}


sub printNewEmailSenderForm {
  my ($html);
  
  $html = <<__HTML;
  <form id="frm_email_sender" name="frm_email_sender" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="/cgi-pl/admin/maintain_email_senders.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Add Email Sender</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <label for="email">Email Address:</label>
      <input type="text" id="email" name="email" value="$email" maxlength=128>
      <label for="m_user">Login Username:</label>
      <input type="text" id="m_user" name="m_user" value="$m_user" maxlength=64>
      <label for="m_user">Login Password:</label>
      <input type="text" id="m_pass" name="m_pass" value="$m_pass" maxlength=64>
      <label for="smtp_server">SMTP Server:</label>
      <input type="text" id="smtp_server" name="smtp_server" value="$smtp_server" maxlength=128>
      <label for="port">Port No.:</label>
      <input type="text" id="port" name="port" value="$port">
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveEmailSender();">                  
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub modifyEmailSender {
  my ($dbh, $ms_id, $email, $m_user, $m_pass, $smtp_server, $port) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE sys_email_sender
    SET email = ?,
        m_user = ?,
        m_pass = ?,
        smtp_server = ?,
        port = ?
    WHERE ms_id = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($email, $m_user, $m_pass, $smtp_server, $port, $ms_id)) {
    $msg = "Unable to update email sender $email. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getEmailSenderDetails {
  my ($dbh, $ms_id) = @_;
  my ($sql, $sth, %result);
  
  $sql = <<__SQL;
  SELECT email, m_user, m_pass, smtp_server, port
    FROM sys_email_sender
    WHERE ms_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($ms_id)) {
    my @data = $sth->fetchrow_array();
    %result = ('email' => $data[0], 'm_user' => $data[1], 'm_pass' => $data[2], 'smtp_server' => $data[3], 'port' => $data[4]);
  }
  $sth->finish;
  
  return %result;
}


sub printEmailSenderEditForm {
  my ($email_sender_ref) = @_;
  my ($html, %email_sender);
  
  %email_sender = %$email_sender_ref;

  $html = <<__HTML;  
  <form id="frm_email_sender" name="frm_email_sender" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="ms_id" name="ms_id" value="$ms_id">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="/cgi-pl/admin/maintain_email_senders.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Edit Email Sender</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <label for="email">Email Address:</label>
      <input type="text" id="email" name="email" value="$email_sender{'email'}" maxlength=128>
      <label for="m_user">Login Username:</label>
      <input type="text" id="m_user" name="m_user" value="$email_sender{'m_user'}" maxlength=64>
      <label for="m_user">Login Password:</label>
      <input type="text" id="m_pass" name="m_pass" value="$email_sender{'m_pass'}" maxlength=64>
      <label for="smtp_server">SMTP Server:</label>
      <input type="text" id="smtp_server" name="smtp_server" value="$email_sender{'smtp_server'}" maxlength=128>
      <label for="port">Port No.:</label>
      <input type="text" id="port" name="port" value="$email_sender{'port'}">
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveEmailSender();">                  
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub deleteEmailSender {
  my ($dbh, $ms_id) = @_;
  my ($ok, $msg, $sql, $sth); 

  $ok = 1;
  $msg = '';

  $sql = <<__SQL;
  DELETE FROM sys_email_sender
    WHERE ms_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($ms_id)) {
    $msg = "Unable to delete this email sender. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getEmailSenderList {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT ms_id, email
    FROM sys_email_sender
    WHERE status = 'A'
    ORDER BY email
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'ms_id' => $data[0], 'email' => $data[1]};
    }
  }
  
  return @result;
}


sub printEmailSenderList {
  my ($ms_list_ref) = @_;
  my ($html, @ms_list);
  
  @ms_list = @$ms_list_ref;
  
  $html = <<__HTML;
  <form id="frm_email_sender" name="frm_email_sender" action="" method="post">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="ms_id" name="ms_id" value="0">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Email Senders</h1>
      <a href="javascript:goHome();" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>      
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed;">
      <thead>
        <tr style="background-color:lightblue">
          <td width=70% align=center valign=center><b>Email Sender</b></td>
          <td align=center valign=center><b>Delete</b></td>
        </tr>
      </thead>
      <tbody>    
__HTML

  foreach my $rec (@ms_list) {
    my $this_ms_id = $rec->{'ms_id'} + 0;
    my $this_email = $rec->{'email'};
    
    $html .= <<__HTML;
    <tr style="background-color:lightyellow">
      <td align=center valign=center style="word-wrap:break-word;"><a href="javascript:editEmailSender($this_ms_id)">$this_email</a></td>
      <td align=center valign=center><input type="button" id="del_es" name="del_es" value="" data-icon="delete" data-iconpos="notext" onClick="deleteEmailSender($this_ms_id)"></td>
    </tr>
__HTML
  }

  $html .= <<__HTML;
      </tbody>
      </table>
      <br>
      <input type="button" id="add_new" name="add_new" value="Add Email Sender" onClick="addEmailSender();" data-icon="plus">                  
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}

