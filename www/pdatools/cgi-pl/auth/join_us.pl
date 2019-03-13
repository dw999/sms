#!/usr/bin/perl

##########################################################################################
# Program: /www/pdatools/cgi-pl/auth/join_us.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-05      AY              Let an applicant be accepted or rejected.
# V1.0.01       2018-07-27      AY              Inform all system administrators if a new
#                                               guy has been accepted.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use URI::Escape;
use Encode qw(decode encode);
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;                                        # Defined on sm_webenv.pl
  
my $approval = allTrim(paramAntiXSS('S'));              # Referrer's approval. 'A' or 'R'.                        
my $token = allTrim(uri_escape(paramAntiXSS('tk')));    # Authentication token. Note: Perl CGI parameters receiving function unescape passed data automatically.

print header(-type=>'text/html', -charset=>'utf-8');

my $dbh = dbconnect($COOKIE_MSG);
my ($ok, $msg, $apply_id, $name, $email, $seed);

$ok = 1;
$msg = '';

if ($approval eq 'A' || $approval eq 'R') {  
  ($ok, $msg, $apply_id, $name, $email, $seed) = loadApplicantInfo($dbh, $token);
  if ($ok) {
    if (verifyApplicantOk($name, $email, $seed, $token)) {
      ($ok, $msg) = setApplicantStatus($dbh, $apply_id, $approval);       # Defined on sm_user.pl
      if ($ok && $approval eq 'A') {
        ($ok, $msg) = informApplicantToJoin($dbh, $name, $email, $token);
        informSysAdminNewGuyAccepted($dbh, $apply_id);
      }
    }
    else {
      $msg = "Applicant verification failure";
      $ok = 0;
    }
  }
}

if ($ok) {
  if ($approval eq 'A') {
    alert("Applicant is accepted, and confirmation email has been sent to him/her.");
  }
  elsif ($approval eq 'R') {
    alert("Applicant is rejected");
  }
}
else {
  alert($msg);
}

redirectTo("/cgi-pl/index.pl");

dbclose($dbh);
#-- End Main Section --#


sub loadApplicantInfo {
  my ($dbh, $token) = @_;
  my ($sql, $sth, $ok, $msg, $apply_id, $name, $email, $seed, $apply_date);
  
  $ok = 1;
  $msg = $name = $email = $seed = '';
  $apply_id = 0;
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT apply_id, name, email, seed, apply_date
      FROM applicant
      WHERE status = 'W'
        AND token = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($token)) {
      ($apply_id, $name, $email, $seed, $apply_date) = $sth->fetchrow_array();
      if ($apply_id <= 0) {
        $msg = "Unable to find the applicant to apply your decision, may be you have done it before.";
        $ok = 0;
      }
    }
    else {
      $msg = $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
    
    #-- Check whether approval period has been passed --#
    if ($ok) {
      if (_isTimeLimitPassed($dbh, $apply_date, '3 00:00:00')) {      # Note: 1. '3 00:00:00' means 3 days, 2. It is defined on sm_user.pl
        setApplicantStatus($dbh, $apply_id, 'T');                     # Mark applicant record status as timeout. Defined on sm_user.pl 
        $msg = "You are too late to approve this applicant, valid period has been passed.";
        $ok = 0;
      }
    }    
  }
  else {
    $msg = "Invalid database connection handler is found, process cannot proceed.";
    $ok = 0;
  }
  
  return ($ok, $msg, $apply_id, $name, $email, $seed);
}


sub verifyApplicantOk {
  my ($name, $email, $seed, $token) = @_;
  my ($ok, $paratext, $chk_name, $chk_email, $chk_seed);
  
  ($ok, $paratext) = _decrypt_str(uri_unescape($token), $seed);           # Defined on sm_user.pl
  
  if ($ok) {
    ($chk_name, $chk_email, $chk_seed) = extractParameters($paratext);
    
    if ($name ne $chk_name || $email ne $chk_email || $seed ne $chk_seed) {
      $ok = 0;
    }
  }
  
  return $ok;
}


sub extractParameters {
  my ($paratext) = @_;
  my ($name, $email, $seed, @buffer);

  $name = $email = $seed = '';
  
  @buffer = split('&', $paratext);
  foreach my $this_param (@buffer) {
    my @parts = split('=', $this_param);
    my $param_name = allTrim($parts[0]);
    my $param_data = allTrim($parts[1]);
    
    if ($param_name =~ /name/) {
      $name = $param_data;    
    }
    elsif ($param_name =~ /email/) {
      $email = $param_data;
    }
    elsif ($param_name =~ /seed/) {
      $seed = $param_data;
    }    
  }
  
  return ($name, $email, $seed);
}


sub informApplicantToJoin {
  my ($dbh, $name, $email, $token) = @_;
  my ($ok, $msg, $sender, $m_user, $m_pass, $smtp_server, $port, $subject, $site_dns, $link, $mail_body);

  ($sender, $m_user, $m_pass, $smtp_server, $port) = getSysEmailSender($dbh);        # Defined on sm_webenv.pl
  $site_dns = getSiteDNS($dbh, 'D');                                                 # Defined on sm_webenv.pl
  
  $name = decode('utf8', $name);
  
  if ($site_dns ne '') {
    $subject = "You are accepted";
    $link = "$site_dns/cgi-pl/user/add_user.pl?tk=$token";
    $mail_body = "Hi $name, \n\n" .
                 "Please follow the link below to finalize the registration process: \n\n" .
                 "$link \n\n" .
                 "Important Notes: \n" .
                 "1. You have 4 days to complete the process. \n" .
                 "2. For security reason, please delete this mail after you complete the registration. \n";
                 
    ($ok, $msg) = sendOutGmail($sender, $email, $m_user, $m_pass, $smtp_server, $port, $subject, $mail_body);        # Defined on sm_webenv.pl
    if (!$ok) {
      $msg = "Unable to send confirmation email to applicant: $msg";
    }   
  }  
  else {
    $msg = "Unable to send confirmation email to applicant due to system error, please let system administrator check for it.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub informSysAdminNewGuyAccepted {
  my ($dbh, $apply_id) = @_;
  my ($ok, $msg, $sql, $sth, $applicant, $referer_username, $referer_alias, $referer_realname, $subject, $mail_content);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  SELECT a.name, b.user_name, b.user_alias, b.name
    FROM applicant a, user_list b
    WHERE a.refer_email = b.email
      AND a.apply_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($apply_id)) {
    ($applicant, $referer_username, $referer_alias, $referer_realname) = $sth->fetchrow_array();
  }
  else {
    $msg = "Unable to inform system administrator a new guy is accepted. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  if ($ok) {
    $referer_username = allTrim($referer_username);
    $referer_alias = allTrim($referer_alias);
    $referer_realname = allTrim($referer_realname);
    
    $subject = "New guy is accepted";
    $mail_content = decode('utf8', "A new guy named $applicant has been accepted by our member $referer_username / $referer_alias / $referer_realname (username / alias / name).");    
    ($ok, $msg) = informSystemAdmin($dbh, $subject, $mail_content);              # Defined on sm_webenv.pl
  }
  
  return ($ok, $msg);
}
