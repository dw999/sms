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
# Program: /www/itnews/cgi-pl/msg/pull_new_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-20      AY              Get newly added message(s) for specified user
#                                               and specified group.
# V1.0.01       2018-09-21      AY              Change parameter passing method as calling
#                                               function getGroupMessage.
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
my $last_sent_msg_only = paramAntiXSS('last_sent_msg_only') + 0;   # 0 = All unread messages, 1 = last sent message only (note: it has been marked as read)
my $omid_list = allTrim(paramAntiXSS('omid_list'));        # ID list of messages of the group. Use to determine which message(s) is/are deleted.

my $dbh = dbconnect($COOKIE_MSG);                          

my @new_messages = ();
my $js_data = '';

if (sessionAlive($COOKIE_MSG, 0)) {                                        # Defined on sm_user.pl
  if ($last_sent_msg_only) {
    #-- Get your last sent message only, since you just send a message --#
    @new_messages = getLastSentMessage($dbh, $group_id, $receiver_id);     # Defined on sm_msglib.pl  
  }
  else {
    #-- Get only those messages you don't read before --#
    my %m_params = ('new_msg_only' => 1);
    @new_messages = getGroupMessage($dbh, $group_id, $receiver_id, \%m_params);     # Defined on sm_msglib.pl
    if (scalar(@new_messages) == 0) {
      #-- It means that another group member just delete his/her message(s), NOT add new message(s). --#
      #-- Note: For private groups, the system may delete messages automatically, include your       --#
      #-- messages. Therefore, '$omid_list' should include messages ID belong to you.                --#  
      @new_messages = getDeletedMessageIdList($dbh, $receiver_id, $omid_list);  
    }
  }
  
  #$js_data = encode_json \@new_messages;
  #-- Note: Since data stored on database has already encoded in UTF-8, and 'encode_json' is by default encoded data with UTF-8. --#
  #--       Therefore, it causes the retrieved data double encoded by UTF-8, and make it to become garbage. So, use latin1       --#
  #--       encoding method as below command, and don't use UTF-8 encoding method to convert data into JSON string format.       --#
  #--       For more information, please see the URL below:                                                                      --#
  #--       https://stackoverflow.com/questions/33802155/perl-json-encode-in-utf-8-strange-behaviour                             --#
  $js_data = JSON->new->latin1->encode(\@new_messages);
}
else {
  $js_data = '[]';
}
  
$js_data =~ s/null/""/g;

print header(-type => 'text/html', -charset => 'utf-8');
print $js_data;

dbclose($dbh);
#-- End Main Section --#


sub getDeletedMessageIdList {
  my ($dbh, $receiver_id, $omid_list) = @_;
  my (@omid, @result);
  
  @omid = split('\|', $omid_list);
  
  foreach my $this_msg_id (@omid) {
    #-- Note: 1. For private group, if one of my message delivery transaction record is deleted, then related message should  --#
    #--          be considered as 'deleted', even the message still exists.                                                   --#
    #--       2. In a private group, all the messages displaying is from my point of view. i.e. A message will be shown, even --#
    #--          it's delivery transaction record for another group member has been deleted. Conversely, A message will not   --#
    #--          be displayed if it's delivery transaction record for me is deleted.                                          --# 
    if (!messageExist($dbh, $receiver_id, $this_msg_id)) {
      push @result, {'msg_id' => $this_msg_id, 'msg_status' => 'deleted'}
    }    
  }
  
  return @result;
}


sub messageExist {
  my ($dbh, $receiver_id, $msg_id) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM message a, msg_tx b
    WHERE a.msg_id = b.msg_id
      AND b.receiver_id = ?
      AND a.msg_id = ?  
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($receiver_id, $msg_id)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 1 : 0;
  }
  else {
    #-- Just play safe, assume the message and it's delivery transaction still exist. --#        
    $result = 1;
  }
  $sth->finish;
    
  return $result;
}
