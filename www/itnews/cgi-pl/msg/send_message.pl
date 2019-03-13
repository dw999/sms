#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/msg/send_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-06      AY              Send message to specified group.
# V1.0.01       2018-08-18      AY              Take care message replying. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use POSIX;
use JSON;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $group_id = paramAntiXSS('group_id') + 0;               # Message group ID
my $sender_id = paramAntiXSS('sender_id') + 0;             # User ID of the message sender
my $message = paramAntiXSS('message');                     # Message
my $op_flag = paramAntiXSS('op_flag');
my $op_user_id = paramAntiXSS('op_user_id') + 0;
my $op_msg = paramAntiXSS('op_msg');

my $dbh = dbconnect($COOKIE_MSG);                          
#my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
#my $user_id = $user_info{'USER_ID'} + 0;

my %result = ();
my $update_token = '';
my $js_data = '';
my $json = '';

if (sessionAlive($COOKIE_MSG, 1)) {
  #-- Send out message --#
  my ($ok, $msg) = sendMessage($dbh, $sender_id, $group_id, $message, '', $op_flag, $op_user_id, $op_msg);      # Defined on sm_msglib.pl

  #-- Get the most updated token and return to the sender --#
  $update_token = getMessageUpdateToken($dbh, $group_id);    # Defined on sm_msglib.pl
  %result = ('update_token' => $update_token);

  $js_data = encode_json \%result;
  $json = <<__JSON;
  {"mg_status": $js_data}
__JSON

  $json =~ s/null/""/g;

  print header(-type => 'text/html', -charset => 'utf-8');
  print $json;
}

dbclose($dbh);
