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
# Program: /www/pdatools/cgi-pl/user/create_user_acct.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-06      DW              Create user account.
# V1.0.01       2018-08-10      DW              Remove using 'crypt' to encrypt user passwords
#                                               due to it's serious limitation (only first 8
#                                               characters are used for encrypted password).
# V1.0.02       2018-09-21      DW              Use new encryption method to protect user passwords.
# V1.0.03       2019-05-30      DW              Inform new user's referrer, he/she has been joined,
#                                               if the referrer is not system administrator.
# V1.0.04       2020-08-06      DW              Create a private group for newly registered user and
#                                               his/her referrer.
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
    if (!isSysAdmin($dbh, $refer)) {
      #-- If new user's referrer is not system administrator, inform him. --#
      $mail_content = decode('utf8', "A new guy $alias / $name (alias / name) who is referred by you has joined us as member.");
      informReferrer($dbh, $refer, $subject, $mail_content);      # Defined on sm_webenv.pl
    }
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
        setApplicantStatus($dbh, $apply_id, 'T');                     # Defined on sm_user.pl
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
      #-- Create a private group between the newly added user and his/her referrer --#
      ($ok, $msg) = createFirstPrivateGroup($dbh, $user, $alias, $name, $refer_email);  
    }
    
    if ($ok) {
      ($ok, $msg) = setApplicantStatus($dbh, $apply_id, 'C');      # Defined on sm_user.pl
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


sub createFirstPrivateGroup {
  my ($dbh, $user, $alias, $name, $refer_email) = @_;
  my ($ok, $msg, $grp_admin_id, $member_id, $group_id);
            
  $ok = 1;
  $msg = '';
            
  #-- Step 1: Try to get user id of the referrer and the newly added user --#
  $grp_admin_id = getUserIdByName($dbh, $user);         # Defined on sm_user.pl
  $member_id = getRefererUserId($dbh, $refer_email);
  
  if ($grp_admin_id > 0 && $member_id > 0) {
    #-- Note: If referrer of the newly created user becomes inactive or newly added user id cannot be retrieved, this process will be skipped. --# 
    #-- Step 2: Create the group --#
    ($ok, $msg, $group_id) = addPrivateGroup($dbh, $alias, 1, 5);
      
    if ($ok) {
      #-- Step 3: Add all persons to group member table --#
      ($ok, $msg) = addGroupMember($dbh, $group_id, $grp_admin_id, $member_id);
    }
      
    if ($ok) {
      #-- Step 4: Send the first message on behalf of the group creator to the invited person --#
      ($ok, $msg) = sendMemberFirstMessage($dbh, $group_id, $grp_admin_id, $name, $alias);
    }    
  }
  
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


sub isSysAdmin {
  my ($dbh, $refer_email) = @_;
  my ($sql, $sth, $role, $result);
  
  $result = 0;
  
  $sql = <<__SQL;
  SELECT user_role 
    FROM user_list
    WHERE email = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($refer_email)) {
    ($role) = $sth->fetchrow_array();
    $result = ($role + 0 == 2)? 1 : 0;
  }
  $sth->finish;
  
  return $result;
}


sub addPrivateGroup {
  my ($dbh, $group_name, $auto_delete, $delete_after) = @_;
  my ($sql, $sth, $ok, $msg, $group_id, $encrypt_key);
  
  $ok = 1;
  $msg = '';  
  $group_id = 0;
  $encrypt_key = _generateRandomStr('A', 32);                # Defined on sm_webenv.pl
  
  $sql = <<__SQL;
  INSERT INTO msg_group
  (group_name, group_type, msg_auto_delete, delete_after_read, encrypt_key, status, refresh_token)
  VALUES
  (?, 1, ?, ?, ?, 'A', '')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_name, $auto_delete, $delete_after, $encrypt_key)) {
    $msg = "Unable to create group. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Retrieve the newly added group id --#
    $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
    if ($sth->execute()) {
      ($group_id) = $sth->fetchrow_array();
      if ($group_id <= 0) {
        $msg = "Unable to retrieve newly created group id by unknown reason.";
        $ok = 0;
      }      
    }
    else {
      $msg = "Unable to retrieve newly created group id. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }

  return ($ok, $msg, $group_id);  
}


sub addGroupMember {
  my ($dbh, $group_id, $user_id, $member_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  #-- This is the group administrator --#
  $sql = <<__SQL;
  INSERT INTO group_member
  (group_id, user_id, group_role)
  VALUES
  (?, ?, '1')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id, $user_id)) {
    $msg = "Unable to add group administrator. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  if ($ok) {    
    #-- This is the group member, the only member. --#
    $sql = <<__SQL;
    INSERT INTO group_member
    (group_id, user_id, group_role)
    VALUES
    (?, ?, '0')
__SQL
  
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($group_id, $member_id)) {
      $msg = "Unable to add group member. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;    
  }
  
  return ($ok, $msg);
}


sub sendMemberFirstMessage {
  my ($dbh, $group_id, $user_id, $name, $alias) = @_;
  my ($ok, $msg, $message);
  
  $message = "I am $name, and my alias is $alias. Please add me to appropriate group(s).";
  ($ok, $msg) = sendMessage($dbh, $user_id, $group_id, $message);               # Defined on sm_msglib.pl
  
  return ($ok, $msg);
}
