#!/usr/bin/perl
##########################################################################################
# Program: event_reminder.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-18      AY              Remind users for scheduled event(s).
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use Encode qw(decode encode);
use WWW::Telegram::BotAPI;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_PDA;                      # Defined on sm_webenv.pl
our $COOKIE_MSG;                      

my $dbh = dbconnect($COOKIE_PDA);
my $dbx = dbconnect($COOKIE_MSG);

if ($dbh ne undef && $dbx ne undef) {
  my ($subject, $body, $from_mail, $from_user, $from_pass, $smtp_server, $port, $api, $has_tg_bot, $bot_ok, $tg_err_msg, %tg_bot_profile, @event_reminders);
  
  @event_reminders = getEventReminders($dbh);
  
  if (scalar(@event_reminders) > 0) {
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbx);           # Defined on sm_webenv.pl
    %tg_bot_profile = getTelegramBotProfile($dbx);                                                 # Defined on sm_webenv.pl
    $has_tg_bot = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
    $bot_ok = ($tg_bot_profile{'http_api_token'} ne '')? 1 : 0;
  
    if ($has_tg_bot) {
      $api = WWW::Telegram::BotAPI->new(
        token => $tg_bot_profile{'http_api_token'}
      ) or $bot_ok = 0;
    }
    
    foreach my $rec (@event_reminders) {
      my $this_reminder_id = $rec->{'reminder_id'} + 0;
      my $this_user_id = $rec->{'user_id'} + 0;
      my $this_event_title = decode('utf8', $rec->{'event_title'});     # Note: Value of $rec->{'event_title'} is UTF-8 encoded. 
      my $this_ev_start = $rec->{'ev_start'};
      my $this_remind_before = $rec->{'remind_before'} + 0;
      my $this_remind_unit = $rec->{'remind_unit'};
      my $this_ev_passed = $rec->{'ev_passed'} + 0;
      
      if ($this_ev_passed) {
        setReminderOff($dbh, $this_reminder_id);
      }
      else {
        if (remindTimeHasReached($dbh, $this_ev_start, $this_remind_before, $this_remind_unit)) {
          my ($to_mail, $tg_id) = getUserInformData($dbx, $this_user_id);    
          $subject = "$this_event_title $this_remind_before " . (($this_remind_before > 1)? "$this_remind_unit" . 's' : $this_remind_unit) . " later";
          $body = "It reminds you that event $this_event_title will start on $this_ev_start";
          
          my ($ok, $msg) = sendOutGmail($from_mail, $to_mail, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl
          if ($ok) {
            if ($bot_ok && $tg_id ne '') {
              #-- As an auxiliary way to inform user new messages, it don't affect the system flow even it is failure. --#
              eval {
                $api->api_request('sendMessage', {
                  chat_id => $tg_id,
                  text    => "$body"
                });
              } or $tg_err_msg = $api->parse_error->{msg};
        
              if ($tg_err_msg ne '') {
                print "Unable to remind user by Telegram. Error: $tg_err_msg\n";      
              }        
            }
            
            setReminderOff($dbh, $this_reminder_id);
          }
          else {
            print "Unable to send event remind email (id: $this_reminder_id). Error: $msg\n"; 
          }
        }
      }
    }
  }
}
else {
  if ($dbh eq undef) {
    print "Unable to connect database pdadb.\n";
  }

  if ($dbx eq undef) {
    print "Unable to connect database msgdb.\n";
  }
}

dbclose($dbh);
dbclose($dbx);
#-- End main section --#


sub getEventReminders {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT a.reminder_id, b.user_id, b.event_title, b.ev_start, a.remind_before, a.remind_unit,
         CASE
           WHEN b.ev_start < CURRENT_TIMESTAMP() THEN 1
           ELSE 0
         END AS ev_passed  
    FROM schedule_reminder a, schedule_event b
    WHERE a.event_id = b.event_id
      AND a.has_informed = 0
    ORDER BY b.ev_start
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'reminder_id' => $data[0], 'user_id' => $data[1], 'event_title' => $data[2], 'ev_start' => $data[3], 'remind_before' => $data[4],
                     'remind_unit' => $data[5], 'ev_passed' => $data[6]};
    }    
  }
  $sth->finish;
  
  return @result;
}


sub setReminderOff {
  my ($dbh, $reminder_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE schedule_reminder
    SET has_informed = 1
    WHERE reminder_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($reminder_id)) {
    $msg = "Unable to turn off event reminder. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub remindTimeHasReached {
  my ($dbh, $ev_start, $remind_before, $remind_unit) = @_;
  my ($sql, $sth, $fire_time, $result);
  
  #-- Step 1: Determine the event reminder firing date and time --#
  $sql = <<__SQL;
  SELECT '$ev_start' - INTERVAL $remind_before $remind_unit
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    ($fire_time) = $sth->fetchrow_array();
  }
  $sth->finish;

  #-- Step 2: Determine whether $fire_time passes current time --#
  if (allTrim($fire_time) ne '') {
    $sql = <<__SQL;
    SELECT CASE
             WHEN '$fire_time' <= CURRENT_TIMESTAMP() THEN 1
             ELSE 0
           END  
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
      ($result) = $sth->fetchrow_array();
    }
    else {
      $result = 0; 
    }
    $sth->finish;
  }
  else {
    #--Play safe --#
    $result = 0;
  }
  
  return $result;
}


sub getUserInformData {
  my ($dbx, $user_id) = @_;
  my ($sql, $sth, $email, $tg_id);
  
  $sql = <<__SQL;
  SELECT email, tg_id
    FROM user_list 
    WHERE user_id = ?
__SQL
  
  $sth = $dbx->prepare($sql);
  if ($sth->execute($user_id)) {
    ($email, $tg_id) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return ($email, $tg_id);
}


