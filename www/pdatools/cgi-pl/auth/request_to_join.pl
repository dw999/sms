#!/usr/bin/perl

##########################################################################################
# Program: /www/pdatools/cgi-pl/auth/request_to_join.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-02      AY              Request to join the messaging system.
# V1.0.01       2018-07-31      AY              Fix unrecognised Chinese characters issue
#                                               on inform email.
# V1.0.02       2018-08-21      AY              Only system administrator can self register
#                                               new user account.
# V1.0.03       2018-12-09      AY              Rewrite UI section by using jQuery Mobile.
# V1.0.04       2019-01-17      AY              Fix hard corded company name issue on 'printRegisteredOkPage'.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use URI::Escape;
use Encode qw(decode encode);
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                      # Both are defined on sm_webenv.pl
our $COOKIE_MSG;
our $PDA_BG_COLOR;

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));   # 'S' = Confirm to join, others go to data input screen.
my $name = allTrim(paramAntiXSS('name'));             # Applicant's name.
my $email = allTrim(paramAntiXSS('email'));           # Applicant's email address.
my $refer = allTrim(paramAntiXSS('refer'));           # Referrer's email address.
my $remark = allTrim(paramAntiXSS('remark'));         # Applicant's remark to referrer.

printFreeHeader('Join Us');                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);

if ($oper_mode eq 'S') {
  my ($ok, $msg, $token, $is_trusted, $user_role, $site, $show_warning);
  
  ($is_trusted, $user_role) = isReferrerTrusted($dbh, $refer);
  if ($is_trusted) {
    if ($email eq $refer && $user_role < 2) {
      #-- Trusted user cannot self register a new user account, but system administrator is allowed to do so. --#
      $show_warning = 1;
    }
    else {
      ($ok, $msg, $token) = saveApplicantInfo($dbh, $name, $email, $refer, $remark);
      if ($ok) {
        informReferrerToApproval($dbh, $name, $refer, $remark, $token);
      }
      else {
        logSystemError($dbh, 0, $msg, "Unable to create applicant record");       # Defined on sm_user.pl
      }      
    }
  }
  
  if ($show_warning) {
    $site = getSiteDNS($dbh, 'D');                     # Defined on sm_webenv.pl
    alert("You should not self register a new user account.");
    redirectTo($site);    
  }
  else {
    printStyleSection();
    printJavascriptSection();
#    printCSS($COOKIE_PDA);
#    printPageHeader("Welcome to Join");                # Defined on sm_webenv.pl  
    printRegistedOkPage($name);
#    printPageFooter();                                 # Defined on sm_webenv.pl      
  }
}
else {
  printStyleSection();
  printJavascriptSection();
#  printCSS($COOKIE_PDA);
#  printPageHeader("Welcome to Join");                # Defined on sm_webenv.pl
  printInputForm();
#  printPageFooter();                                 # Defined on sm_webenv.pl
}

dbclose($dbh);
#-- End Main Section --#


sub isReferrerTrusted {
  my ($dbh, $refer) = @_;
  my ($sql, $sth, $user_role, $result);
  
  $result = 0;
  
  if ($dbh) {
    #-- Here imply a potential issue: If a guy has more than one user accounts by using same email address, if role on one of these accounts --#
    #-- is non-trusted user (user_role = 0), and this non-trusted user account record is picked up, then this referrer will be considered    --#
    #-- untrusted. Therefore, we need to put the higher user role record go first to resolve this issue.                                     --# 
    $sql = <<__SQL;
    SELECT user_role
      FROM user_list
      WHERE status = 'A'
        AND email = ?
      ORDER BY user_role DESC  
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($refer)) {
      ($user_role) = $sth->fetchrow_array();
      $user_role += 0;
      $result = ($user_role >= 1)? 1 : 0;
    }
    $sth->finish;    
  }

  return ($result, $user_role);  
}


sub saveApplicantInfo {
  my ($dbh, $name, $email, $refer, $remark) = @_;
  my ($ok, $msg, $sql, $sth, $key, $paratext, $token);
  
  $ok = 1;
  $msg = $key = $paratext = $token = '';
  
  if ($dbh) {
    $key = _generateRandomStr('A', 32);                    # Defined on sm_webenv.pl
    $paratext = "name=$name&email=$email&seed=$key"; 
    ($ok, $token) = _encrypt_str($paratext, $key);         # Defined on sm_user.pl
    if ($ok) {
      $token = uri_escape($token);
      
      $sql = <<__SQL;
      INSERT INTO applicant
      (name, email, refer_email, remark, apply_date, status, seed, token)
      VALUES
      (?, ?, ?, ?, CURRENT_TIMESTAMP(), 'W', ?, ?)
__SQL

      $sth = $dbh->prepare($sql);
      if (!$sth->execute($name, $email, $refer, $remark, $key, $token)) {
        $msg = $sth->errstr;
        $ok = 0;
      }
      $sth->finish;      
    }
    else {
      $msg = "Unable to encrypt applicant data: $paratext";
      $ok = 0;
    }
  }
  else {
    $msg = "Invalid database connection handler";
    $ok = 0;    
  }
  
  return ($ok, $msg, $token);  
}


sub informReferrerToApproval {
  my ($dbh, $name, $refer, $remark, $token) = @_;
  my ($ok, $msg, $sender, $m_user, $m_pass, $smtp_server, $port, $subject, $site_dns, $accept_url, $reject_url, $mail_body);

  ($sender, $m_user, $m_pass, $smtp_server, $port) = getSysEmailSender($dbh);        # Defined on sm_webenv.pl
  $site_dns = getSiteDNS($dbh, 'D');                                                 # Defined on sm_webenv.pl
  
  #-- Since Email::MIME used on 'sendOutGmail' for email body is UTF-8 encoded, so that $name and $remark must be decoded into UTF-8 codedec --#
  #-- before pass into this function. Otherwise, unrecognised characters will be shown on the email body.                                    --#
  $name = decode('utf8', $name);
  $remark = decode('utf8', $remark);
  
  if ($site_dns ne '') {  
    $subject = "Someone wants to join us, please take a look.";
    $accept_url = "$site_dns/cgi-pl/auth/join_us.pl?S=A&tk=$token";
    $reject_url = "$site_dns/cgi-pl/auth/join_us.pl?S=R&tk=$token";
    $mail_body = "A new guy wants to join us. His/her name is listed below, and he/she may say something to you also: \n\n" .
                 "Name: $name \n" .
                 "Message to you: $remark \n\n" .
                 "There are two links for you to choose. Clicking on the first link will accept this applicant to join, but the second link is used for rejection. \n\n" .
                 "Accept: $accept_url \n\n" .
                 "Reject: $reject_url \n\n" .
                 "You have 3 days to make the decision.\n\n" .
                 "Important Note: Please delete this mail after you make your decision.\n";
  
    ($ok, $msg) = sendOutGmail($sender, $refer, $m_user, $m_pass, $smtp_server, $port, $subject, $mail_body);        # Defined on sm_webenv.pl
    if (!$ok) {
      $subject = "Applicant approval email cannot be sent";
      $mail_body = $msg;
      _informAdminSystemProblem($dbh, '', $subject, $mail_body);          # Defined on sm_user.pl
    }    
  }
  else {
    $subject = "Applicant approval email cannot be sent";
    $mail_body = "The problem is highly possible related to site DNS settings, please check for it.";
    _informAdminSystemProblem($dbh, '', $subject, $mail_body);            # Defined on sm_user.pl
  }  
}


sub printRegistedOkPage {
  my ($name) = @_;
  my ($message, $company_name, $copy_right);
  
  $company_name = getDecoyCompanyName();      # Defined on sm_webenv.pl
  
  $message = "Hi $name, <br><br>" .
             "Your application has been sent to approval, and you should get our reply within 3 days. However, if you don't get the mail, please contact your referrer.<br><br>" .
             "P.R. Team <br>" .
             "$company_name";

  $copy_right = getDecoySiteCopyRight();      # Defined on sm_webenv.pl
    
  print <<__HTML;
  <form id="frmRegister" name="frmRegister" action="/cgi-pl/index.pl" method="post">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <h1>Thanks You</h1>
    </div>
    
    <div data-role="content" style="ui-content">
      $message
      <br>
      <br>
      <input type=button id="return_home" name="return_home" value="Return" onClick="this.form.submit();">
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


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>    
  <script type="text/javascript" src="/js/common_lib.js"></script>
  
  <script type="text/javascript">
    function goRegister() {
      var this_name = allTrim(document.getElementById("name").value);
      var this_email = allTrim(document.getElementById("email").value);
      var this_refer = allTrim(document.getElementById("refer").value);
      
      if (this_name == "") {
        alert("Your name is compulsory.");
        document.getElementById("name").focus();
        return false;
      }
      
      if (this_email == "") {
        alert("Your email address is compulsory.");
        document.getElementById("email").focus();
        return false;
      }
      
      if (this_refer == "") {
        alert("Your referrer's email address is compulsory.");
        document.getElementById("refer").focus();
        return false;
      }
      
      document.getElementById("oper_mode").value = "S";
      document.getElementById("frmRegister").submit();
    }
  </script>
__JS
}


sub printStyleSection {
  print <<__STYLE;
  <style>
    .a_message {
      width:98%;
      height:120px;
      max-height:200px;
    }
  </style>
__STYLE
}


sub printInputForm {
  my ($red_dot, $copy_right);
  
  $red_dot = "<font color='red'>*</font>";
  $copy_right = getDecoySiteCopyRight();      # Defined on sm_webenv.pl

  print <<__HTML;
  <form id="frmRegister" name="frmRegister" action="" method="post" data-ajax="false">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/index.pl" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Welcome to Join</h1>
    </div>
  
    <div data-role="content" style="ui-content">
      <label for="name"><b>Your Name $red_dot:</b></label>
      <input type=text id="name" name="name" value="$name" maxlength=125 required>
  
      <label for="email"><b>Your Email $red_dot:</b></label>  
      <input type=email id="email" name="email" value="$email" maxlength=125 required placeholder="Enter your email address">

      <label for="refer"><b>Referrer's Email $red_dot:</b></label>
      <input type=email id="refer" name="refer" value="$refer" maxlength=125 required placeholder="Enter referrer's email address">
  
      <label for="remark"><b>Any Words to Your Referrer?</b></label>
      <textarea id="remark" name="remark" data-role="none" class="a_message">$remark</textarea>
      <br>
      <br>

      <input type=button id="go_reg" name="go_reg" value="Register" onClick="goRegister();">  
      <br>  
      <b>Note:</b> Input item with $red_dot is compulsory.
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


