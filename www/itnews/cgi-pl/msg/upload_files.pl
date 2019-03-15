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
# Program: /www/itnews/cgi-pl/msg/upload_files.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-08-02      AY              Upload file. Include photo images, video clip,
#                                               sound file and any document files. However, no
#                                               Perl and Unix shell scripts are allowed.
# V1.0.01       2018-08-27      AY              Add message reply consideration.  
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use POSIX;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $group_id = paramAntiXSS('group_id') + 0;               # Message group ID.
my $sender_id = paramAntiXSS('sender_id') + 0;             # Uploader's user ID.
my $ul_ftype = allTrim(paramAntiXSS('ul_ftype'));          # Upload file types. Valid values are 'photo', 'sound' and 'file'.
my $ul_file = param('ul_file');                            # Upload file (since it is an object, so that just bring it on without any modification). 
my $caption = allTrim(paramAntiXSS('caption'));            # Photo caption.
my $op_flag = allTrim(paramAntiXSS('op_flag'));            # Possible values are blank and 'R' (reply).
my $op_user_id = paramAntiXSS('op_user_id') + 0;           # Original sender id of the reply message or file.
my $op_msg = paramAntiXSS('op_msg');                       # Partial of the reply message (30 UTF-8 characters).

my $dbh = dbconnect($COOKIE_MSG);                          
my $ok = 1;
my $msg = '';
my $update_token = '';

if (sessionAlive($COOKIE_MSG, 1)) {                                        # Defined on sm_user.pl
  ($ok, $msg, $update_token) = uploadFileToMessageGroup($dbh, $group_id, $sender_id, $ul_ftype, $ul_file, $caption, $op_flag, $op_user_id, $op_msg);      # Defined on sm_msglib.pl
  if (!$ok) {
    _logSystemError($dbh, $sender_id, $msg, 'File upload failure');        # Defined on sm_user.pl
    $update_token = 'upload_failed';
  }
}

print header(-type => 'text/html', -charset => 'utf-8');
print $update_token;

dbclose($dbh);
#-- End Main Section --#

