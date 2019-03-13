#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/msg/pull_prev_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-09-18      AY              Load previous message block for specified user
#                                               and specified group. 
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
my $receiver_id = paramAntiXSS('receiver_id') + 0;         # User ID of message receiver. 
my $first_msg_id = paramAntiXSS('first_msg_id') + 0;       # It means the ID of the first message which has already loaded.  
my $rows_limit = paramAntiXSS('rows_limit') + 0;           # Maximum number of messages will be retrieved.

my $dbh = dbconnect($COOKIE_MSG);                          

my @prev_messages = ();
my $js_data = '';

if (sessionAlive($COOKIE_MSG, 1)) {                        # Defined on sm_user.pl, please also note that pulling old messages is an user initiative action, so it should extend the session period.
  #-- Note: Sorting order of previous messages is in reverse order of sending time, and it is much convenient as data set is passed back to calling program. --# 
  @prev_messages = getPrevGroupMessage($dbh, $group_id, $receiver_id, $first_msg_id, $rows_limit);     # Defined on sm_msglib.pl
  
  #-- Note: Since data stored on database has already encoded in UTF-8, and 'encode_json' is by default encoded data with UTF-8. --#
  #--       Therefore, it causes the retrieved data double encoded by UTF-8, and make it to become garbage. So, use latin1       --#
  #--       encoding method as below command, and don't use UTF-8 encoding method to convert data into JSON string format.       --#
  #--       For more information, please see the URL below:                                                                      --#
  #--       https://stackoverflow.com/questions/33802155/perl-json-encode-in-utf-8-strange-behaviour                             --#
  $js_data = JSON->new->latin1->encode(\@prev_messages);
}
else {
  $js_data = '[]';
}
  
$js_data =~ s/null/""/g;

print header(-type => 'text/html', -charset => 'utf-8');
print $js_data;

dbclose($dbh);
#-- End Main Section --#

