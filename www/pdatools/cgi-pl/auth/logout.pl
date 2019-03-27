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
# Program: /www/pdatools/cgi-pl/auth/logout.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-23      DW              Logout the decoy web site. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_PDA);

my $c_ref = getSessionInfo($COOKIE_PDA);                   # Defined on sm_user.pl
my %sess_info = %$c_ref;
my $sess_code = $sess_info{'SESS_CODE'};
my $user_cookie;
my %user_info = ();
my $url;

#-- Step 1: Delete session record --#
_deleteSession($COOKIE_PDA, $sess_code);                   # Defined on sm_user.pl

#-- Step 2: Clear cookie --#
$user_info{'SESS_CODE'} = '';
$user_cookie = cookie(-name => $COOKIE_PDA, -value => \%user_info, -path => '/', -secure => 1);
print header(-charset => 'utf-8', -cookie => $user_cookie);

#-- Step 3: Redirect to decoy site login page --#
$url = "/cgi-pl/index.pl";                         
redirectTo($url);

dbclose($dbh);

