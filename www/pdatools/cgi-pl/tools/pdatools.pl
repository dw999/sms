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
# Program: /www/pdatools/cgi-pl/tools/pdatools.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-01      DW              Load up the first page of PDA tools.
# V1.0.01       2018-12-16      DW              Set cookie expiry period and enforce pass via SSL.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $COOKIE_PDA;
our $PRINTHEAD;

my $user = allTrim(paramAntiXSS('user'));                  # User name

my $dbh = dbconnect($COOKIE_MSG);
my $dbp = dbconnect($COOKIE_PDA);
my $user_id = 0;

if ($dbh && $dbp) {
  $user_id = getUserIdByName($dbh, $user);          # Defined on sm_user.pl
  if ($user_id > 0) {
    showPdaTools($user_id);
  }
  else {
    print header(-type=>'text/html', -charset=>'utf-8');
    alert("Unable to retrieve your profile, please try again. If the problem insists, please contact support.");
    redirectTo("/cgi-pl/auth/login.pl?user=$user");    
  }
}
else {
  print header(-type=>'text/html', -charset=>'utf-8');
  alert("You has issue as connect to PDA Tools web site, please try again. If the problem insists, please contact support.");
  redirectTo("/cgi-pl/auth/login.pl?user=$user");
}

dbclose($dbh);
dbclose($dbp);


sub showPdaTools {
  my ($user_id) = @_;
  my ($ok, $msg, $sess_code, $user_cookie, %user_info);

  ($ok, $msg, $sess_code) = createSessionRecord($dbp, $user_id);      # Defined on sm_webenv.pl
  if ($ok) {
    #-- Set cookie for logon user --#
    $user_info{'SESS_CODE'} = $sess_code;
    $user_cookie = cookie(-name => $COOKIE_PDA, -value => \%user_info, -path => '/', -expires => '+2d', -secure => 1);  
    print header(-charset => 'utf-8', -cookie => $user_cookie);
    $PRINTHEAD = 1;
  
    #-- Then go to the first page of PDA tools --#
    redirectTo("/cgi-pl/tools/select_tools.pl");        
  }
  else {
    alert("Unable to create session, please login again");
    redirectTo("/cgi-pl/index.pl");
  }
}
