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
# Program: /www/itnews/cgi-pl/auth/logout.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-19      DW              Logout the messaging system.
# V1.0.01       2018-08-21      DW              Go to login page as logout.
# V1.0.02       2019-01-21      DW              Go to a arbitrary decoy site as logout. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);

my $c_ref = getSessionInfo($COOKIE_MSG);                   # Defined on sm_user.pl
my %sess_info = %$c_ref;
my $sess_code = $sess_info{'SESS_CODE'};
my $user_cookie;
my %user_info = ();
my $url;

#-- Step 1: Delete session record --#
_deleteSession($COOKIE_MSG, $sess_code);                   # Defined on sm_user.pl

#-- Step 2: Clear cookie --#
$user_info{'SESS_CODE'} = '';
$user_cookie = cookie(-name => $COOKIE_MSG, -value => \%user_info, -path => '/', -secure => 1);
print header(-charset => 'utf-8', -cookie => $user_cookie);

#-- Step 3: Redirect to a randomly selected decoy site. --#
#-- Note: It is better to close the page after quit SMS. Otherwise, your --#
#--       messages can still be shown on page by clicking on the 'back'  --#
#--       button.                                                        --#
$url = selectSiteForVisitor($dbh);                         # Defined on sm_webenv.pl
redirectTo($url);

dbclose($dbh);
#-- End Main Section --#


sub closeCurrentTab {
  print <<__JS;
  <script>
    var win = window.open("", "_self");    
    win.close();  
  </script>
__JS
}
