#!/usr/bin/perl

##########################################################################################
# Program: /www/pdatools/cgi-pl/user/create_user_acct.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-06      AY              Create user account.
# V1.0.01       2018-08-10      AY              Remove using 'crypt' to encrypt user passwords
#                                               due to it's serious limitation (only first 8
#                                               characters are used for encrypted password).
# V1.0.02       2018-09-21      AY              Use new encryption method to protect user passwords. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use Encode qw(decode encode);
use CGI qw/:standard/;
use Authen::Passphrase::BlowfishCrypt;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                        # Both are defined on sm_webenv.pl
our $COOKIE_MSG;                                  

my $apply_id = paramAntiXSS('apply_id') + 0;    
my $user = allTrim(paramAntiXSS('user'));
my $alias = allTrim(paramAntiXSS('alias'));
my $happy_passwd = paramAntiXSS('happy_passwd1');
my $unhappy_passwd = paramAntiXSS('unhappy_passwd1');

print header(-type=>'text/html', -charset=>'utf-8');

my $dbh = dbconnect($COOKIE_MSG);
my ($ok, $msg, $token, $name, $email, $refer);

($ok, $msg, $token, $name, $email, $refer) = loadApplicantInfo($dbh, $apply_id);  

if ($ok) {
  if (userExist($dbh, $user)) {
    $msg = "User name <$user> has already existed.";
    $ok = 0;    
  }
  
  if (aliasExist($dbh, $alias)) {
    $msg = "Alias <$alias> has already existed.";
    $ok = 0;
  }
    
  if ($ok) {
    ($ok, $msg) = createUserAccount($dbh, $apply_id, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $refer);  
  }
  
  if ($ok) {
    my $referer = getRefererName($dbh, $refer);
    my $subject = "New member has joined";
    my $mail_content = decode('utf8', "A new guy $user / $alias / $name (username / alias / name) who is referred by $referer has joined us as member.");
    informSystemAdmin($dbh, $subject, $mail_content);             # Defined on sm_webenv.pl
  }
}

if ($ok) {
  alert("Your account is created, you may login now.");
  redirectTo("/cgi-pl/auth/login.pl");
}
else {
  alert($msg);
  redirectTo("/cgi-pl/user/add_user.pl?tk=$token&user=$user");    
}

dbclose($dbh);
#-- End Main Section --#


sub loadApplicantInfo {
  my ($dbh, $apply_id) = @_;
  my ($sql, $sth, $ok, $msg, $token, $name, $email, $apply_date, $refer);
  
  $ok = 1;
  $msg = $email = '';
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT token, name, email, apply_date, refer_email
      FROM applicant
      WHERE status = 'A'
        AND apply_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($apply_id)) {
      ($token, $name, $email, $apply_date, $refer) = $sth->fetchrow_array();
      if (allTrim($token) eq '') {
        $msg = "Unable to find your apply record";
        $ok = 0;
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
        setApplicantStatus($dbh, $apply_id, 'T');                     # Timeout.
        $msg = "You are too late to finalize your registration, valid period has been passed. Please apply again.";
        $ok = 0;
      }      
    }    
  }
  else {
    $msg = "Invalid database connection handler is found, process cannot proceed.";
    $ok = 0;
  }
  
  return ($ok, $msg, $token, $name, $email, $refer);    
}


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
  my ($dbh, $apply_id, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $refer_email) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = addUserAccount($dbh, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $refer_email);
    
    if ($ok) {
      ($ok, $msg) = setApplicantStatus($dbh, $apply_id, 'C');
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "System error is found, user account creation process cannot proceed. Please try again later.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub addUserAccount {
  my ($dbh, $user, $name, $email, $alias, $happy_passwd, $unhappy_passwd, $refer_email) = @_;
  my ($ok, $msg, $sql, $sth, $referer_id, $crypted_happy_passwd, $crypted_unhappy_passwd, $ppr);
  
  $ok = 1;
  $msg = '';  
  $referer_id = getRefererUserId($dbh, $refer_email);
  
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
  if (!$sth->execute($user, $alias, $name, $crypted_happy_passwd, $crypted_unhappy_passwd, $email, $referer_id)) {
    $msg = "Unable to add user account. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getRefererUserId {
  my ($dbh, $refer_email) = @_;
  my ($sql, $sth, $result);
  
  $result = 0;
  
  $sql = <<__SQL;
  SELECT user_id
    FROM user_list
    WHERE email = ?
      AND status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($refer_email)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  $sth->finish;
  
  return $result;
}


sub getRefererName {
  my ($dbh, $refer_email) = @_;
  my ($sql, $sth, $result);
  
  $result = 'N/A';
  
  $sql = <<__SQL;
  SELECT user_name, user_alias, name
    FROM user_list
    WHERE email = ?
      AND status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($refer_email)) {
    my @data = $sth->fetchrow_array();
    $result = allTrim($data[0]) . " / " . allTrim($data[1]) . " / " . allTrim($data[2]) . " (username / alias / name)";
  }
  $sth->finish;
  
  return $result;
}
