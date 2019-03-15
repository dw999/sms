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
# Program: new_message_inform.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-18      AY              Inform offline users who get new messages.
# V1.0.01       2018-08-24      AY              Inform offline users with new messages via
#                                               Telegram.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use WWW::Telegram::BotAPI;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                      # Defined on sm_webenv.pl

my $cookie_name = $COOKIE_MSG;      
my $dbh = dbconnect($cookie_name);

if ($dbh ne undef) {
  my ($ok, $msg, $url, $subject, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, %informed_user, @inform_rec);
  my ($api, $has_tg_bot, $bot_ok, %tg_bot_profile);

  $url = getSiteDNS($dbh, 'D');                                                                  # Defined on sm_webenv.pl
  $subject = "Greetings from your friends";
  ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);           # Defined on sm_webenv.pl
  $body = "Your friends miss you so much, please click the link below to get their greetings: \n\n$url\n";
  %tg_bot_profile = getTelegramBotProfile($dbh);                                                 # Defined on sm_webenv.pl
  $has_tg_bot = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
  $bot_ok = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
  %informed_user = ();
  
  if ($has_tg_bot) {
    $api = WWW::Telegram::BotAPI->new(
      token => $tg_bot_profile{'http_api_token'}
    ) or $bot_ok = 0;
  }
    
  deleteInformRecordWithError($dbh, 3);
  
  @inform_rec = getInformRecords($dbh);
  foreach my $rec (@inform_rec) {
    my $to_user_id = $rec->{'user_id'} + 0;
    my $status = uc(allTrim($rec->{'status'}));
    my $period = $rec->{'period'};
    my $to_mail = $rec->{'email'};
    my $tg_id = allTrim($rec->{'tg_id'});          # It is the Telegram chat ID of this SMS user.
    my $tg_err_msg = '';
    
    if ($informed_user{$to_user_id} + 0 != 1) {
      if ($status eq 'A') {
        #-- It may contain multiple new message inform records for one user, try not to send more than one email to him/her. --#
        ($ok, $msg) = sendOutGmail($from_mail, $to_mail, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl
        if ($ok) {
          deleteInformRecord($dbh, $to_user_id, $period);
          $informed_user{$to_user_id} = 1;
        }
        else {
          logDownSysError($dbh, $to_user_id, $msg, 'Unable to inform user new message by Gmail');
          increaseErrorCount($dbh, $to_user_id, $period);
        }
      
        if ($bot_ok && $tg_id ne '') {
          #-- As an auxiliary way to inform user new messages, it don't affect the system result even it is failure. --#
          #-- That means the user may receive multiple Telegram messages due to email sending is failure.            --#
          eval {
            $api->api_request('sendMessage', {
              chat_id => $tg_id,
              text    => 'You have new message'
            });
          } or $tg_err_msg = $api->parse_error->{msg};
        
          if ($tg_err_msg ne '') {
            logDownSysError($dbh, $to_user_id, $tg_err_msg, 'Telegram Message Sending Error');      
          }        
        }
      }
      else {
        deleteInformRecord($dbh, $to_user_id, $period);
      }
    }
    else {
      deleteInformRecord($dbh, $to_user_id, $period);
    }
  }
}
else {
  print "Unable to connect database msgdb. \n";
}
#-- End Main Section --#


sub deleteInformRecordWithError {
  my ($dbh, $error_limit) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM new_msg_inform
    WHERE try_cnt >= ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($error_limit)) {
    $msg = "Unable to remove user inform record with errors. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getInformRecords {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT a.user_id, a.period, b.email, b.tg_id, b.status
    FROM new_msg_inform a, user_list b
    WHERE a.user_id = b.user_id
    ORDER BY a.user_id, a.period
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'user_id' => $data[0], 'period' => $data[1], 'email' => $data[2], 'tg_id' => $data[3], 'status' => $data[4]};
    }    
  }
  $sth->finish;
  
  return @result;
}


sub deleteInformRecord {
  my ($dbh, $to_user_id, $period) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM new_msg_inform
    WHERE user_id = ?
      AND period = ? 
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($to_user_id, $period)) {
    $msg = "Unable to delete new message inform record (user id = $to_user_id, time = $period). Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub increaseErrorCount {
  my ($dbh, $to_user_id, $period) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE new_msg_inform
    SET status = 'E',
        try_cnt = try_cnt + 1
    WHERE user_id = ?
      AND period = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($to_user_id, $period)) {
    $msg = "Unable to update error counter of a new message inform record (user id = $to_user_id, time = $period). Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub logDownSysError {
  my ($dbh, $user_id, $detail_msg, $brief_msg) = @_;
  my ($sql, $sth, $browser_signature);
  
  $user_id += 0;
  $detail_msg =~ s/'/''/g;
  $brief_msg =~ s/'/''/g;
  $browser_signature = 'Command line program';
  
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
