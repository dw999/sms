#!/usr/bin/perl
##########################################################################################
# Program: /www/perl_lib/sm_user.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-24      AY              Library functions used for user authentication.
# V1.0.01       2018-08-10      AY              Remove using 'crypt' to encrypt user passwords
#                                               due to it's serious limitation (only first 8
#                                               characters are used for encrypted password).
# V1.0.02       2018-09-21      AY              Apply another method for encrypted user password
#                                               checking.
# V1.0.03       2018-11-06      AY              Remove session IP address restriction to let users
#                                               connect via Tor browser. See function 'sessionAlive'.
# V1.0.04       2019-01-07      AY              Add connection mode 2 and 3 handling methods on function
#                                               'authenticateLoginUser'.
# V1.0.05       2019-01-14      AY              Add function 'setApplicantStatus'.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use URI::Escape;
use Encode qw(decode encode);
use Crypt::CBC;
use CGI qw/:standard/;
use Authen::Passphrase::BlowfishCrypt;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_PDA;                                      # Both are defined on sm_webenv.pl
our $COOKIE_MSG;                                  


sub authenticateLoginUser {
  my ($user, $pass, $latitude, $longitude) = @_;
  my ($dbh, $sth, $sql, $login_status, $message, $happy_ppr, $unhappy_ppr, $connection_mode, $redirect_url, @data);

  $login_status = 0;
  $message = '';
  
  $dbh = dbconnect($COOKIE_MSG);
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT user_id, happy_passwd, unhappy_passwd, email, status
      FROM user_list
      WHERE user_name = ?
__SQL

    $sth = $dbh->prepare($sql);
    $sth->execute($user);
    @data = $sth->fetchrow_array();
    $sth->finish;
    
    my ($user_id, $happy_passwd, $unhappy_passwd, $email, $status) = ($data[0], $data[1], $data[2], $data[3], $data[4]);

    $user_id += 0;
    
    if ($user_id > 0) {
      $connection_mode = getSysSettingValue($dbh, 'connection_mode') + 0;      
      $happy_ppr = Authen::Passphrase->from_crypt($happy_passwd);
      $unhappy_ppr = Authen::Passphrase->from_crypt($unhappy_passwd);
      
      if ($happy_ppr->match($pass)) {
        if ($status eq 'A') {
          if ($connection_mode == 0) {
            #-- Login in via email --#
            ($login_status, $message) = _sendMessageAccessLinkMail($dbh, $user_id, $email);            
            $redirect_url = "/cgi-pl/tools/pdatools.pl?user=$user";
          }
          elsif ($connection_mode == 1) {
            #-- Login directly --#
            ($login_status, $message, $redirect_url) = _buildMessageAccessLink($dbh, $user_id);
          }
          elsif ($connection_mode == 2) {
            #-- Login directly --#
            ($login_status, $message, $redirect_url) = _buildMessageAccessLink($dbh, $user_id);            
          }
          elsif ($connection_mode == 3) {
            #-- Login in via email --#
            ($login_status, $message) = _sendMessageAccessLinkMail($dbh, $user_id, $email);            
            $redirect_url = "/cgi-pl/tools/pdatools.pl?user=$user";            
          }
          else {
            #-- Misc. system setting 'connection_mode' has invalid value --#
            $message = "Authentication server is malfunction, please return later.";            
            $login_status = 0;
          }
          
          if ($login_status == 1) {
            _resetLoginFailureCounter($dbh, $user_id);  
          }
        }
        elsif ($status eq 'D') {
          #-- Deactivated user --#
          $message = "Authentication server is down, please try again later.";
          $login_status = 0;          
        }
        elsif ($status eq 'U') {
          #-- Arrested user may be cracked by force --#
          if (!_beCracked($dbh, $user_id)) {
            _informAdminUnhappyUserIsCracked($dbh, $user);
            _logCrackedEvent($dbh, $user_id);
          }          
          _logUnhappyLoginTime($dbh, $user_id, $latitude, $longitude);
          $login_status = 1;
          $redirect_url = "/cgi-pl/tools/pdatools.pl?user=$user";
        }
        else {
          #-- System has problem --#
          _informAdminSystemProblem($dbh, $user, "Invalid user status $status", "The system find that user status of $user is abnormal, please take a look.");
          $message = "The server is under maintenance, please try again later.";
          $login_status = 0;
        }
      }
      elsif ($unhappy_ppr->match($pass)) {
        #-- Be careful: If an user has been arrested (mark unhappy) before, don't let him/her uses his/her 'unhapppy' account again. Otherwise, he/she --#
        #-- will not trigger 'unhappy' operation as he/she is arrested again, due to his previous 'unhappy' record(s).                                 --#  
        if (_isFirstUnhappyLogin($dbh, $user_id)) {       
          _markUserStatusAsUnhappy($dbh, $user_id);
          if ($connection_mode == 1) {
            _informRelatedGroupMembers($dbh, $user_id, $latitude, $longitude);
          }
          else {
            #-- Note: Function '_informAllRelatedParties' must be run after function '_markUserStatusAsUnhappy'. Otherwise, warning email --#
            #--       will be sent to the guy who is arrested, if he/she is system administrator.                                         --#            
            _informAllRelatedParties($dbh, $user_id, $user, $latitude, $longitude);
          }
          #-- Note: Function '_kickOutFromMessageGroups' MUST be run after function '_informAllRelatedParties'. Otherwise, incorrect --#
          #--       result will be obtained.                                                                                         --#
          _kickOutFromMessageGroups($dbh, $user_id);           
        }
        _logUnhappyLoginTime($dbh, $user_id, $latitude, $longitude);
        $login_status = 1;
        $redirect_url = "/cgi-pl/tools/pdatools.pl?user=$user";
      }
      else {
        #-- Invalid password --#
        _increaseLoginFailureCounter($dbh, $user_id);
        _logHackingHistory($dbh, $user_id);
        $message = "Authentication server is out of order, please try again later.";
        $login_status = 0;
      }
    }
    else {
      #-- Invalid user --#
      $message = "Unable to contact the authentication server, please try again later.";
      $login_status = 0;
    }

    dbclose($dbh);     
  }
  else {
    #-- Unable to connect the database --#
    $message = "The server is very busy, please try again later. If this problem persists, please contact your referrer.";
    $login_status = 0;
  }
  
  return ($login_status, $message, $redirect_url);
}


sub _encrypt_str {
  my ($plaintext, $key) = @_;
  my ($ok, $cipher, $encrypted);
  
  $encrypted = '';
  $ok = 0;
  
  $cipher = Crypt::CBC->new(-key => $key, -cipher => 'Rijndael');
  if ($cipher) {
    $encrypted = $cipher->encrypt($plaintext);
    $ok = 1;
  }
  
  return ($ok, $encrypted);  
}


sub _decrypt_str {
  my ($encrypted, $key) = @_;
  my ($ok, $cipher, $decrypted);
  
  $decrypted = '';
  $ok = 0;
  
  $cipher = Crypt::CBC->new(-key => $key, -cipher => 'Rijndael');
  if ($cipher) {
    $decrypted = $cipher->decrypt($encrypted);
    $ok = 1;
  }
  
  return ($ok, $decrypted);  
}


sub _sendMessageAccessLinkMail {
  my ($dbh, $user_id, $to_mail) = @_;
  my ($login_status, $message, $ok, $plaintext, $token, $key, $add_time, $seed);
  
  $login_status = 1;
  $message = $plaintext = $token = '';
  
  $add_time = _getCurrentTimestamp($dbh);            # Defined on sm_webenv.pl
  $seed = _generateRandomStr('A', 32);               # Defined on sm_webenv.pl
  $key = allTrim($seed);

  $plaintext = "user_id=$user_id&seed=$seed";
  ($ok, $token) = _encrypt_str($plaintext, $key); 
  if ($ok) {
    #-- Keep in mind that the encrypted token is escaped, therefore, it must be unescaped the token before using. --#
    $token = uri_escape($token);

    if ($token ne '') {
      my ($ok, $msg) = _writeToLoginQueue($dbh, $token, $add_time, $seed, $user_id);
      if ($ok) {
        ($ok, $msg) = _sendLoginMail($dbh, $user_id, $to_mail, $token, $add_time);
        if (!$ok) {
          _logSystemError($dbh, $user_id, $msg, "Unable to send login email");
          $message = "Unable to take you into authentication process (code #4), please try again later.";
          $login_status = 0;                        
        }
      }
      else {
        _logSystemError($dbh, $user_id, $msg, "Unable to save login queue record");
        $message = "Unable to take you into authentication process (code #3), please try again later.";
        $login_status = 0;              
      }
    }
    else {
      $message = "Unable to take you into authentication process (code #2), please try again later.";
      $login_status = 0;      
    }    
  }
  else {
    $message = "Unable to take you into authentication process (code #1), please try again later.";
    $login_status = 0;
  }
    
  return ($login_status, $message);
}


sub _buildMessageAccessLink {
  my ($dbh, $user_id) = @_;
  my ($login_status, $message, $ok, $plaintext, $token, $key, $add_time, $seed, $login_url);
  
  $login_status = 1;
  $message = $plaintext = $token = '';
  
  $add_time = _getCurrentTimestamp($dbh);            # Defined on sm_webenv.pl
  $seed = _generateRandomStr('A', 32);               # Defined on sm_webenv.pl
  $key = allTrim($seed);

  $plaintext = "user_id=$user_id&seed=$seed";
  ($ok, $token) = _encrypt_str($plaintext, $key); 
  if ($ok) {
    #-- Keep in mind that the encrypted token is escaped, therefore, it must be unescaped the token before using. --#
    $token = uri_escape($token);

    if ($token ne '') {
      my ($ok, $msg) = _writeToLoginQueue($dbh, $token, $add_time, $seed, $user_id);
      if ($ok) {
        ($ok, $msg, $login_url) = _buildLoginLink($dbh, $token);
        if (!$ok) {
          _logSystemError($dbh, $user_id, $msg, "Unable to build login link");
          $message = "Unable to take you into authentication process (code #5), please try again later.";
          $login_status = 0;                        
        }
      }
      else {
        _logSystemError($dbh, $user_id, $msg, "Unable to save login queue record");
        $message = "Unable to take you into authentication process (code #3), please try again later.";
        $login_status = 0;              
      }
    }
    else {
      $message = "Unable to take you into authentication process (code #2), please try again later.";
      $login_status = 0;      
    }    
  }
  else {
    $message = "Unable to take you into authentication process (code #1), please try again later.";
    $login_status = 0;
  }
    
  return ($login_status, $message, $login_url);
}


sub _writeToLoginQueue {
  my ($dbh, $token, $add_time, $seed, $user_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  $user_id += 0;  
  
  $sql = <<__SQL;
  INSERT INTO login_token_queue
  (token, token_addtime, token_seed, status, user_id)
  VALUES
  (?, ?, ?, ?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($token, $add_time, $seed, 'A', $user_id)) {
    $msg = $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub _sendLoginMail {
  my ($dbh, $user_id, $to_mail, $token, $add_time) = @_;
  my ($ok, $msg, $site_dns, $from_mail, $subject, $from_user, $from_pass, $smtp_server, $port, $body, $login_url);
  
  $site_dns = getSiteDNS($dbh, 'M');            # Defined on sm_webenv.pl
  
  if ($site_dns ne '') {
    $subject = "Your subscribed news list";
    $login_url = "$site_dns/cgi-pl/read_news.pl?tk=$token";  
    $body = "Please click the link below to access the latest news: \n\n$login_url\n\nTimestamp: $add_time \n\n ";
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);                                # Defined on sm_webenv.pl
  
    ($ok, $msg) = sendOutGmail($from_mail, $to_mail, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl
  }
  else {
    $msg = "Unable to get message site URL";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub _buildLoginLink {
  my ($dbh, $token) = @_;
  my ($ok, $msg, $site_dns, $login_url);
  
  $ok = 1;
  $msg = '';
  
  $site_dns = getSiteDNS($dbh, 'M');            # Defined on sm_webenv.pl
  
  if ($site_dns ne '') {
    $login_url = "$site_dns/cgi-pl/read_news.pl?tk=$token";
  }
  else {
    $msg = "Unable to get message site URL";
    $ok = 0;    
  }
  
  return ($ok, $msg, $login_url);
}


sub _logSystemError {
  my ($dbh, $user_id, $detail_msg, $brief_msg) = @_;
  my ($sql, $sth, $browser_signature);
  
  $user_id += 0;
  $detail_msg =~ s/'/''/g;
  $brief_msg =~ s/'/''/g;
  $browser_signature = $ENV{'HTTP_USER_AGENT'};
  
  $sql = <<__SQL;
  INSERT INTO sys_error_log
  (user_id, brief_err_msg, detail_err_msg, log_time, browser_signature)
  VALUES
  (?, ?, ?, CURRENT_TIMESTAMP(), ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user_id, $brief_msg, $detail_msg, $browser_signature);
  $sth->finish;
}


#-- It is the public access interface of internal function '_logSystemError' --#
sub logSystemError {
  my ($dbh, $user_id, $detail_msg, $brief_msg) = @_;

  _logSystemError($dbh, $user_id, $detail_msg, $brief_msg);  
}


sub _resetLoginFailureCounter {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth);
  
  $user_id += 0;
  
  $sql = <<__SQL;
  UPDATE user_list
    SET login_failed_cnt = 0
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user_id);
  $sth->finish;
}


sub _beCracked {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $result);
 
  $user_id += 0;
 
  $sql = <<__SQL;
  SELECT cracked
    FROM user_list
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user_id);
  ($result) = $sth->fetchrow_array();
  $sth->finish;
  $result += 0;
  
  return $result;
}


sub _informAdminUnhappyUserIsCracked {
  my ($dbh, $user) = @_;
  my ($sql, $sth, $subject, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, $cracked_user, @data, @admins);
  
  $sql = <<__SQL;
  SELECT user_name, user_alias, email
    FROM user_list
    WHERE user_role = 2
      AND status = 'A' 
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (@data = $sth->fetchrow_array()) {
    push @admins, {'name' => $data[0], 'alias' => $data[1], 'email' => $data[2]};
  }
  $sth->finish;
  
  if (scalar(@admins) > 0) {
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);                      # Defined on sm_webenv.pl
    $subject = "Cracking News";
  
    foreach my $rec (@admins) {
      my $this_admin = (allTrim($rec->{'alias'}) ne '')? $rec->{'alias'} : $rec->{'name'};
      my $this_email = $rec->{'email'};
      
      $body = "Hi $this_admin, \n\n" .
              "Please note that $user has cracked his/her last record. Be careful. \n\n" .
              "Best Regards, \n" .
              "Information Team.\n";
      
      sendOutGmail($from_mail, $this_email, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl      
    }     
  }
}


sub _logCrackedEvent {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth);
  
  $user_id += 0;
  
  $sql = <<__SQL;
  UPDATE user_list
    SET cracked = 1,
        cracked_date = CURRENT_TIMESTAMP()
    WHERE user_id = ?    
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute($user_id);
  $sth->finish;  
}


sub _logUnhappyLoginTime {
  my ($dbh, $user_id, $latitude, $longitude) = @_;
  my ($sql, $sth, $browser_agent);

  $user_id += 0;
  $latitude += 0;
  $longitude += 0;  
  $browser_agent = $ENV{'HTTP_USER_AGENT'};
  
  $sql = <<__SQL;
  INSERT INTO unhappy_login_history
  (user_id, login_time, loc_longitude, loc_latitude, browser_signature)
  VALUES
  (?, CURRENT_TIMESTAMP(), ?, ?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id, $longitude, $latitude, $browser_agent)) {
    my $err_msg = $sth->errstr; 
    _logSystemError($dbh, $user_id, $err_msg, "Unable to save unhappy login record");
  }
}


sub _informAdminSystemProblem {
  my ($dbh, $user, $subject, $content) = @_;
  my ($sql, $sth, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, @data, @admins);
  
  $sql = <<__SQL;
  SELECT user_name, user_alias, email
    FROM user_list
    WHERE user_role = 2
      AND status = 'A' 
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (@data = $sth->fetchrow_array()) {
    push @admins, {'name' => $data[0], 'alias' => $data[1], 'email' => $data[2]};
  }
  $sth->finish;
  
  if (scalar(@admins) > 0) {
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);        # Defined on sm_webenv.pl
    
    foreach my $rec (@admins) {
      my $this_admin = (allTrim($rec->{'alias'}) ne '')? $rec->{'alias'} : $rec->{'name'};
      my $this_email = $rec->{'email'};
      
      $body = "Hi $this_admin, \n\n" .
              ((allTrim($content) eq '')? "Something unusual of this user <$user> is found, please take a look. \n\n" : "$content \n\n") .
              "Best Regards, \n" .
              "Information Team.\n";
      
      sendOutGmail($from_mail, $this_email, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl      
    }     
  }  
}


sub _isFirstUnhappyLogin {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $user_id += 0;
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM unhappy_login_history
    WHERE user_id = ?  
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user_id);
  ($cnt) = $sth->fetchrow_array();
  $sth->finish;
  $cnt += 0;
  $result = ($cnt == 0)? 1 : 0;
  
  return $result;
}


sub _kickOutFromMessageGroups {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $ok, $msg, $is_group_admin, $sys_admin_id, @msg_groups);

  $ok = 1;
  $msg = '';
  $is_group_admin = 0;
  $user_id += 0;

  #-- Step 1: Find all message groups which this guy involves --#
  $sql = <<__SQL;
  SELECT group_id, group_role
    FROM group_member
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @msg_groups, {'group_id' => $data[0], 'group_role' => $data[1]};
      $is_group_admin = ($data[1] + 0 == 1)? 1 : $is_group_admin; 
    }    
  }
  else {
    $msg = $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Step 2: If this guy heads one or more group(s), find a system administrator to replace his/her position. Otherwise, just --#
    #--         kick him/her out from all the involved group(s).                                                                 --#
    if (scalar(@msg_groups) > 0 && $is_group_admin) {
      #-- Select a system administrator who may need to take over those group(s) which have been headed by this guy. --#
      #-- Note: The worst situation is that all system administrators are arrested, then $sys_admin_id will be 0. if --#
      #--       it is the case, just kick that arrested guy from all the group(s), and let those group(s) operate    --#
      #--       without administrator. Hopefully, it would be fixed later manually.                                  --#
      $sys_admin_id = _selectSysAdminInCharge($dbh);
    }
    
    if ($is_group_admin && $sys_admin_id > 0) {
      foreach my $rec (@msg_groups) {
        my $this_group_id = $rec->{'group_id'} + 0;
        my $this_group_role = $rec->{'group_role'} + 0;
      
        if ($this_group_role == 1) {
          if (_isSoleGroupAdmin($dbh, $this_group_id, $user_id)) {
            my ($this_ok, $this_msg) = _addSysAdminToGroup($dbh, $this_group_id, $sys_admin_id);
            if ($this_ok) {
              loadGroupMeesagesForNewMember($dbh, $this_group_id, $sys_admin_id);        # Defined on sm_msglib.pl
            }
          }
        }
        
        _kickOutFromGroup($dbh, $this_group_id, $user_id);
      }
    }
    else {
      _kickOut($dbh, $user_id);
    }
  }
  else {
    #-- Since the situation is very serious, then use the last resort to just kick out this guy from all the groups. The only problem --#
    #-- is that some message group(s) have no administrator, if this guy is the sole administrator of those group(s).                 --#
    _kickOut($dbh, $user_id);
  }
}


sub _selectSysAdminInCharge {
  my ($dbh) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT a.user_id, count(*) AS cnt
    FROM user_list a, group_member b
    WHERE a.user_id = b.user_id
      AND a.user_role = 2
      AND a.status = 'A'
    GROUP BY a.user_id
    ORDER BY cnt
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    #-- Note: Just need the first record. The rule is that who holds less group(s) will be selected out. --#
    my @data = $sth->fetchrow_array();
    $result = $data[0] + 0;
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub _isSoleGroupAdmin {
  my ($dbh, $group_id, $user_id) = @_;
  my ($sql, $sth, $cnt, $result, @data, @members);

  $result = 1;            # Assume he/she is the sole group administrator.
  
  #-- Note: System administrator have same rights of group administrator in a message group. Therefore, if it    --#
  #--       has at least one more system administrator as group member, the group still be considered with group --#
  #--       administrator even this system administrator is just ordinary member of the group.                   --#
  $sql = <<__SQL;
  SELECT a.group_role, b.user_id
    FROM group_member a, user_list b
    WHERE a.user_id = b.user_id
      AND a.group_id = ?
      AND (a.group_role = '1'
       OR b.user_role = 2)
      AND a.user_id <> ?
      AND b.status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($group_id, $user_id)) {
    while (@data = $sth->fetchrow_array()) {      
      if ($data[0] + 0 == 1) {    # Another group administrator is found.
        $result = 0;
      }
      else {
        push @members, $data[1];  
      }

      last if ($result == 0);      
    }
    $sth->finish;
    
    if ($result == 1 && scalar(@members) > 0) {
      #-- If no another group administrator is found, promote the first found system administrator as group administrator. --#
      my $this_user_id = $members[0];
      
      $sql = <<__SQL;
      UPDATE group_member
        SET group_role = '1'
        WHERE group_id = ?
          AND user_id = ?
__SQL

      $sth = $dbh->prepare($sql);
      if ($sth->execute($group_id, $this_user_id)) {
        $result = 0;
      }
      $sth->finish;
    }
  }
  else {
    #-- Play safe to let another system administrator join in this group as group administrator. --#
    $result = 1;
  }
    
  return $result;
}


sub _addSysAdminToGroup {
  my ($dbh, $group_id, $user_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO group_member
  (group_id, user_id, group_role)
  VALUES
  (?, ?, '1')
__SQL
  
  $sth = $dbh->prepare($sql);  
  if (!$sth->execute($group_id, $user_id)) {
    $msg = "Unable to put system administrator (id = $user_id) to head group (id = $group_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub _kickOutFromGroup {
  my ($dbh, $group_id, $user_id) = @_;
  my ($sql, $sth, $msg);
  
  $user_id += 0;
  
  $sql = <<__SQL;
  DELETE FROM group_member
    WHERE group_id = ?
      AND user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($group_id, $user_id)) {
    $msg = "Unable to kick an unhappy user (id = $user_id) from group (id = $group_id), take action immediately! Error: " . $sth->errstr;
    _logSystemError($dbh, $user_id, $msg, "Unable to kick unhappy user");
  }
  $sth->finish;    
}


sub _kickOut {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $msg);
  
  $user_id += 0;
  
  $sql = <<__SQL;
  DELETE FROM group_member
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id)) {
    $msg = "Unable to kick an unhappy user (id = $user_id), take action immediately! Error: " . $sth->errstr;
    _logSystemError($dbh, $user_id, $msg, "Unable to kick unhappy user");
  }
  $sth->finish;  
}


sub _informRelatedGroupMembers {
  my ($dbh, $user_id, $latitude, $longitude) = @_;
  my ($sql, $sth, $message, @msg_groups);
  
  $message = "I am very unhappy. I am currently on position ($longitude, $latitude).";
  
  #-- Step 1: Find all message groups which this guy involves --#
  $sql = <<__SQL;
  SELECT group_id
    FROM group_member
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @msg_groups, $data[0];
    }    
  }
  $sth->finish;
  
  foreach my $this_group_id (@msg_groups) {
    sendMessage($dbh, $user_id, $this_group_id, $message);     # Defined on sm_msglib.pl 
  }
}


sub _informAllRelatedParties {
  my ($dbh, $user_id, $user, $latitude, $longitude) = @_;
  my ($sql, $sth, $subject, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, @data, @inform_users);

  $user_id += 0;
  #-- Since Email::MIME used on 'sendOutGmail' for email body is UTF-8 encoded, so that $user must be decoded into UTF-8 codedec --#
  #-- before pass into this function. Otherwise, unrecognised characters will be shown on the email body.                        --#
  $user = decode('utf8', $user);  
  $latitude += 0;
  $longitude += 0;
  
  #-- Step 1: Get all non-administrative members who had communicated with the arrested user before --# 
  $sql = <<__SQL;
  SELECT DISTINCT b.user_name, b.user_alias, b.email
    FROM group_member a, user_list b
    WHERE a.user_id = b.user_id
      AND a.group_id IN (SELECT DISTINCT group_id
                           FROM group_member
                           WHERE user_id = ?)
      AND b.status = 'A'
      AND b.user_role <= 1 
      AND a.user_id <> ?
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user_id, $user_id);
  while (@data = $sth->fetchrow_array()) {
    push @inform_users, {'name' => $data[0], 'alias' => $data[1], 'email' => $data[2]};
  }
  $sth->finish;
  
  #-- Step 2: Get all administrators --#
  $sql = <<__SQL;
  SELECT user_name, user_alias, email
    FROM user_list
    WHERE user_role = 2
      AND status = 'A'
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (@data = $sth->fetchrow_array()) {
    push @inform_users, {'name' => $data[0], 'alias' => $data[1], 'email' => $data[2]};
  }
  $sth->finish;

  #-- Step 3: Send out email --#
  if (scalar(@inform_users) > 0) {
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);                      # Defined on sm_webenv.pl
    $subject = "Unhappy News";
        
    foreach my $rec (@inform_users) {
      my $this_user = (allTrim($rec->{'alias'}) ne '')? decode('utf8', $rec->{'alias'}) : decode('utf8', $rec->{'name'});     # Same reason as $user is decoded.
      my $this_email = $rec->{'email'};
      my $message = "$user is very unhappy. He/She is currently on position ($longitude, $latitude).";  
      
      $body = "Hi $this_user, \n\n" .
              "$message \n\n" .
              "Best Regards, \n" .
              "Information Team.\n";
      
      sendOutGmail($from_mail, $this_email, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl      
    }     
  }
}


sub _markUserStatusAsUnhappy {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $err_msg);

  $user_id += 0;  

  $sql = <<__SQL;
  UPDATE user_list
    SET status = 'U'
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id)) {
    $err_msg = $sth->errstr;
    _logSystemError($dbh, $user_id, $err_msg, "Unable to mark user as unhappy");
  }
}


sub _increaseLoginFailureCounter {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $cnt);
  
  $user_id += 0;

  $sql = <<__SQL;
  SELECT login_failed_cnt
    FROM user_list
    WHERE user_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute($user_id);
  ($cnt) = $sth->fetchrow_array();
  $cnt += 1;
  $sth->finish;
   
  $sql = <<__SQL;
  UPDATE user_list
    SET login_failed_cnt = ?
    WHERE user_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($cnt, $user_id);
  $sth->finish;
}


sub _logHackingHistory {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $ipv4_addr, $cnt);
  
  $ipv4_addr = allTrim($ENV{'REMOTE_ADDR'});
  $user_id += 0;
  
  if ($dbh && $ipv4_addr ne '' && $user_id > 0) {
    #-- Step 1: Check whether hacking record of given user exists or not --#
    $sql = <<__SQL;
    SELECT COUNT(*) AS cnt
      FROM hack_history
      WHERE user_id = ?
        AND ipv4_addr = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id, $ipv4_addr)) {
      ($cnt) = $sth->fetchrow_array();      
    }
    $sth->finish;
    
    #-- Step 2: If record of same hacker for same user has already existed, update attacking counter and last hacking time. Otherwise, add --#
    #--         a new hacking record for it.                                                                                               --#              
    if ($cnt > 0) {
      $sql = <<__SQL;
      UPDATE hack_history
        SET last_hack_time = CURRENT_TIMESTAMP(),
            hack_cnt = hack_cnt + 1
        WHERE user_id = ?
          AND ipv4_addr = ?    
__SQL
      $sth = $dbh->prepare($sql);
      $sth->execute($user_id, $ipv4_addr);
      $sth->finish;
    }
    else {
      $sql = <<__SQL;
      INSERT INTO hack_history
      (ipv4_addr, user_id, first_hack_time, last_hack_time, hack_cnt, ip_blocked)
      VALUES
      (?, ?, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 1, 0)
__SQL
      $sth = $dbh->prepare($sql);
      $sth->execute($ipv4_addr, $user_id);
      $sth->finish;
    }    
  }
}


sub isTokenValid {
  my ($dbh, $token) = @_;
  my ($sql, $sth, $user_id, $ok, $key, $timestamp, $status, $decrypt_str, $user_id_chk, $seed, $result);
  
  if ($dbh) {
    #-- Step 1: Get user id, encryption key and record timestamp for given token. --#
    $sql = <<__SQL;
    SELECT user_id, token_seed, token_addtime, status
      FROM login_token_queue
      WHERE token = ?
__SQL

    $sth = $dbh->prepare($sql);
    $sth->execute($token);
    ($user_id, $key, $timestamp, $status) = $sth->fetchrow_array();
    $sth->finish;
    
    if ($user_id > 0 && allTrim($key) ne '' && allTrim($timestamp) ne '' && $status eq 'A') {
      #-- Step 2: Decrypt the login token to extract stored user id and the encryption key, then compare them with the data  --#
      #--         extracting from the database. Note: It must unescape passed token value before give it into the decryption --#
      #--         function, since it is the original value (format) when it is encrypted.                                    --#
      ($ok, $decrypt_str) = _decrypt_str(uri_unescape($token), $key);
      if ($ok) {
        ($user_id_chk, $seed) = _resolvePassParameters($decrypt_str);
        
        if ($user_id != $user_id_chk || allTrim($key) ne allTrim($seed)) {
          #-- Data is not matched, the token is fabricated. --#
          $result = 0;
        }
        else {
          if (_isTimeLimitPassed($dbh, $timestamp, '0:10:0.0')) {      # Time limit of an authentication token is 10 minutes since it is created.        
            #-- Time limit assigned to the token has been passed --#
            _markLoginTokenTimeout($dbh, $token);
            $result = 0;
          }
          else {
            #-- It is a valid token --#
            _markLoginTokenIsReady($dbh, $token);      # Set login token status to 'R' (ready to be used).
            $result = 1;  
          }
        }
      }
      else {
        #-- Unexpected system problem --#
        $result = 0;  
      }      
    }
    else {
      #-- Login queue with the given token is not found or invalid --#
      $result = 0;
    }
  }
  else {
    #-- Data connection handler is invalid --#
    $result = 0;
  }
  
  return $result;  
}


sub _resolvePassParameters {
  my ($decrypt_profile) = @_;
  my ($user_id, $seed, @buffer);

  $user_id = 0;
  $seed = '';
  
  @buffer = split('&', $decrypt_profile);
  foreach my $this_param (@buffer) {
    my @parts = split('=', $this_param);
    my $param_name = allTrim($parts[0]);
    my $param_data = allTrim($parts[1]);
    
    if ($param_name =~ /user_id/) {
      $user_id = $param_data + 0;    
    }
    elsif ($param_name =~ /seed/) {
      $seed = $param_data;
    }    
  }
  
  return ($user_id, $seed);
}


sub _isTimeLimitPassed {
  my ($dbh, $timestamp, $interval) = @_;        # Note: Time interval '$interval' is in MariaDB time format
  my ($sql, $sth, $current_time, $token_time_limit, $time_diff, $result);
  
  if ($dbh) {
    #-- Step 1: Calculate token time limit --#    
    $sql = <<__SQL;
    SELECT ADDTIME(?, ?) AS token_time_limit
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($timestamp, $interval)) {
      ($token_time_limit) = $sth->fetchrow_array();
      $sth->finish;
      
      #-- Step 2: Check whether the token time limit has been passed --#
      $sql = <<__SQL;
      SELECT TIMESTAMPDIFF(second, CURRENT_TIMESTAMP(), ?) AS tdi 
__SQL

      $sth = $dbh->prepare($sql);
      if ($sth->execute($token_time_limit)) {
        ($time_diff) = $sth->fetchrow_array();
        $sth->finish;
        
        $time_diff += 0;
        if ($time_diff >= 0) {
          $result = 0;
        }
        else {
          $result = 1; 
        }        
      }
      else {
        $result = 1;
      }
    }
    else {
      $result = 1;
    }
  }
  else {
    $result = 1;
  }
  
  return $result;
}


sub _markLoginTokenIsReady {
  my ($dbh, $token) = @_;
  my ($sql, $sth);
  
  if ($dbh) {
    $sql = <<__SQL;
    UPDATE login_token_queue
      SET status = 'R'
      WHERE token = ?    
__SQL
    
    $sth = $dbh->prepare($sql);
    $sth->execute($token);
    $sth->finish;
  }  
}


sub _markLoginTokenTimeout {
  my ($dbh, $token) = @_;
  my ($sql, $sth);
  
  if ($dbh) {
    $sql = <<__SQL;
    UPDATE login_token_queue
      SET status = 'T'
      WHERE token = ?    
__SQL
    
    $sth = $dbh->prepare($sql);
    $sth->execute($token);
    $sth->finish;
  }  
}


sub _markLoginTokenUsed {
  my ($dbh, $token) = @_;
  my ($sql, $sth);
  
  if ($dbh) {
    $sql = <<__SQL;
    UPDATE login_token_queue
      SET status = 'U',
          token_usetime = CURRENT_TIMESTAMP()
      WHERE token = ?    
__SQL
    
    $sth = $dbh->prepare($sql);
    $sth->execute($token);
    $sth->finish;
  }
}


sub setLoginTokenUsed {
  my ($dbh, $token) = @_;
  
  _markLoginTokenUsed($dbh, $token);
}


sub getUserIdFromToken {
  my ($dbh, $token) = @_;
  my ($sql, $sth, $user_id);
  
  if ($dbh) {
    #-- Note: Only status 'R' token will be extracted for security measure (Prevent attacker use old token to login to the system) --#
    $sql = <<__SQL;
    SELECT user_id
      FROM login_token_queue
      WHERE token = ?
        AND status = 'R'
__SQL

    $sth = $dbh->prepare($sql);
    $sth->execute($token);
    ($user_id) = $sth->fetchrow_array();
    $sth->finish;
    
    $user_id += 0;
  }
  else {
    #-- Data connection handler is invalid --#
    $user_id = 0;
  }
  
  return $user_id;  
}


sub getUserIdByName {
  my ($dbh, $user) = @_;
  my ($sql, $sth, $user_id);
  
  $user_id = 0;
  
  $sql = <<__SQL;
  SELECT user_id
    FROM user_list
    WHERE user_name = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute($user);
  ($user_id) = $sth->fetchrow_array();
  $sth->finish;
  $user_id += 0;
  
  return $user_id;
}


sub getSessionInfo {
  my ($cookie_name) = @_;
  my ($db, $sess_code, $user_id, $sess_until, $ip_address, $http_user_agent, $secure_key, $status, %cookie, %result);
  
  $cookie_name = allTrim($cookie_name);
  
  if ($cookie_name eq $COOKIE_PDA || $cookie_name eq $COOKIE_MSG) {
    $db = dbconnect($cookie_name);
    if ($db) {
      %cookie = cookie($cookie_name);
      $sess_code = $cookie{'SESS_CODE'};
      ($user_id, $sess_until, $ip_address, $http_user_agent, $secure_key, $status) = _getSessionDetails($db, $sess_code);
      %result = ('SESS_CODE' => $sess_code, 'USER_ID' => $user_id, 'VALID' => $sess_until, 'IP_ADDRESS' => $ip_address,
                 'HTTP_USER_AGENT' => $http_user_agent, 'SECURE_KEY' => $secure_key, 'STATUS' => $status);      
      dbclose($db);
    }
    else {
      %result = ();
    }
  }
  else {
    %result = ();
  }
  
  return \%result;
}


sub _getSessionDetails {
  my ($db, $sess_code) = @_;
  my ($sql, $sth, $user_id, $sess_until, $ip_address, $http_user_agent, $secure_key, $status);
  
  $sql = <<__SQL;
  SELECT user_id, sess_until, ip_address, http_user_agent, secure_key, status
    FROM web_session
    WHERE sess_code = ?
__SQL
  
  $sth = $db->prepare($sql);
  if ($sth->execute($sess_code)) {
    ($user_id, $sess_until, $ip_address, $http_user_agent, $secure_key, $status) = $sth->fetchrow_array();    
  }
  $sth->finish;
  
  return ($user_id, $sess_until, $ip_address, $http_user_agent, $secure_key, $status);
}


sub _isSessionTimeLimitPassed {
  my ($cookie_name, $sess_limit) = @_;
  my ($dbh, $sth, $sql, $indc, $result);
  
  $result = 1; 
  
  #-- Note: The server time zone must be UTC + 8 (i.e. HK time), even it is not at Hong Kong. Otherwise, unexpected result will be obtained. --#
  #--       Therefore, it implies one server will just serve users in one time zone only.                                                    --#
  $dbh = dbconnect($cookie_name);
  if ($dbh) {
    $sql = <<__SQL;
    SELECT TIMESTAMPDIFF(second, CURRENT_TIMESTAMP(), ?) AS tdi
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($sess_limit)) {
      ($indc) = $sth->fetchrow_array();
      $result = ($indc >= 0)? 0 : 1;
    }
    $sth->finish;    
  }
  dbclose($dbh);
  
  return $result;
}


sub _isUserValid {
  my ($cookie_name, $user_id) = @_;
  my ($dbh, $sth, $sql, $status, $result);
  
  $result = 1; 
    
  $dbh = dbconnect($cookie_name);
  if ($dbh) {
    $sql = <<__SQL;
    SELECT status
      FROM user_list
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id)) {
      ($status) = $sth->fetchrow_array();
      #-- Note: If status of an user is 'U' (i.e. be arrested or in danger), he/she still be allowed to login to the decoy site. --#
      $result = ($status eq 'A' || $status eq 'U')? 1 : 0;
    }
    $sth->finish;    
  }
  dbclose($dbh);
  
  return $result;
}


sub sessionAlive {
  my ($cookie_name, $extend_session) = @_;
  my ($sess_code, $user_id, $sess_limit, $ip_address, $curr_ip_addr, $user_agent, $curr_user_agent, $status, $alive, $c_ref, %cookie);
  
  $alive = 1;
  $curr_ip_addr = allTrim($ENV{'REMOTE_ADDR'});
  $curr_user_agent = allTrim($ENV{'HTTP_USER_AGENT'});
  $extend_session = ($extend_session eq undef)? 1 : $extend_session; 
  
  $c_ref = getSessionInfo($cookie_name);
  %cookie = %$c_ref;
  ($sess_code, $user_id, $sess_limit, $ip_address, $user_agent, $status) = (allTrim($cookie{'SESS_CODE'}), $cookie{'USER_ID'} + 0, allTrim($cookie{'VALID'}), allTrim($cookie{'IP_ADDRESS'}), allTrim($cookie{'HTTP_USER_AGENT'}), allTrim($cookie{'STATUS'}));
   
  if ($sess_code eq '' || $user_id <= 0 || $sess_limit eq '' || $ip_address eq '' || $user_agent eq '' || $status ne 'A') {
    #-- Warning (2018-12-03):                                                                                                               --#
    #-- User sometimes experiences an issue that session is expired without obvious reason. i.e. The session expired which doesn't cause by --#
    #-- the reasons below. Therefore, this situation is either caused by cookie lost or unable to extract back-end session data. However,   --#
    #-- the cause of this issue is still unknown. This problem is often happened on a moving mobile device, so that it may be caused by     --#
    #-- interruption of connection.                                                                                                         --#     
    $alive = 0;
  }
  elsif (_isSessionTimeLimitPassed($cookie_name, $sess_limit)) {
    _deleteSession($cookie_name, $sess_code);
    $alive = 0;
  }
  elsif ($user_agent ne $curr_user_agent) {
    #-- It is highly possible the current session has been infiltrated by hacker --#
    _deleteSession($cookie_name, $sess_code);
    $alive = 0;    
  }
  #-- 2018-11-06: It is more secure to let user connect via Tor browser, but exit node of Tor browser session will be changed periodically, --#
  #--             and hence the connected IP address. Therefore, after consider the pro and con, I decide to remove IP address restriction. --#
#  elsif ($ip_address ne $curr_ip_addr) {
#    #-- Possible cases:                                                                                                                --#
#    #-- 1. Cookie may have been stolen by hacker and the hacker try to construct a valid session to steal messages of the current user --#
#    #-- 2. Current user establish a VPN connection after login to the system.                                                          --#
#    #-- 3. Current user change internet connection after login to the system. e.g. from LTE to WiFi                                    --#
#    _deleteSession($cookie_name, $sess_code);
#    $alive = 0;
#  }
  elsif (!_isUserValid($COOKIE_MSG, $user_id)) {   # Note: User list is on msgdb only.
    #-- Possible cases:                               --# 
    #-- 1. User has been locked as he/she still login --#
    _deleteSession($cookie_name, $sess_code);
    $alive = 0;    
  }
  
  if ($alive && $extend_session) {
    #-- Extend session valid period --#
    _extendSessionValidTime($cookie_name, $sess_code);
  }
    
  return $alive;
}


sub _deleteSession {
  my ($cookie_name, $sess_code) = @_;
  my ($db, $sql, $sth, $ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  $db = dbconnect($cookie_name);
  
  if ($db) {
    $sql = <<__SQL;
    DELETE FROM web_session
      WHERE sess_code = ?
__SQL

    $sth = $db->prepare($sql);
    if (!$sth->execute($sess_code)) {
      $msg = $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  else {
    $msg = "Unable to connect database to delete session";
    $ok = 0;    
  }
  
  dbclose($db);

  return ($ok, $msg);  
}


sub _extendSessionValidTime {
  my ($cookie_name, $sess_code) = @_;
  my ($db, $sql, $sth, $ok, $msg, $sess_limit);
  
  $ok = 1;
  $msg = '';
  
  $db = dbconnect($cookie_name);
  
  if ($db) {
    $sess_limit = setSessionValidTime();              # Defined on sm_webenv.pl
    
    $sql = <<__SQL;
    UPDATE web_session
      SET sess_until = ? 
      WHERE sess_code = ?
__SQL

    $sth = $db->prepare($sql);
    if (!$sth->execute($sess_limit, $sess_code)) {
      $msg = $sth->errstr;
      $ok = 0;
    }
    $sth->finish;    
  }
  else {
    $msg = "Unable to connect database to extend session period";
    $ok = 0;        
  }
  
  dbclose($db);
  
  return ($ok, $msg);
}


sub getUserRole {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $result);
  
  $result = 0;
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT user_role
      FROM user_list
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id)) {
      ($result) = $sth->fetchrow_array();
      $result += 0;
    }
    $sth->finish;    
  }
  
  return $result;
}


sub getUserName {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, $result, @data);

  $result = '';
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT user_name, user_alias
      FROM user_list
      WHERE user_id = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id)) {
      @data = $sth->fetchrow_array();
      $result = (allTrim($data[1]) ne '')? $data[1] : $data[0]; 
    }
    $sth->finish;
  }
  
  return $result;
}


sub setApplicantStatus {
  my ($dbh, $apply_id, $status) = @_;
  my ($sql, $sth, $ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE applicant
    SET status = ?
    WHERE apply_id = ?
__SQL

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($status, $apply_id)) {
    $msg = "Unable to update applicant status. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}
  

1;