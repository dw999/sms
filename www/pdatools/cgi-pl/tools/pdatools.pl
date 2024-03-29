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
# V1.0.02       2019-04-26      DW              Fix a security hole.
# V1.0.03       2019-04-28      DW              Further harden the fixed security hole.  
# V1.0.04       2022-01-07      DW              Use CGI::Cookie to create cookie in order to
#                                               add 'httpOnly' flag to it to increase security.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use CGI::Cookie;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $COOKIE_PDA;
our $PRINTHEAD;

my $user = allTrim(paramAntiXSS('user'));                  # User name
my $sess_code = allTrim(paramAntiXSS('sess_code'));        # Session code

my $dbh = dbconnect($COOKIE_MSG);
my $dbp = dbconnect($COOKIE_PDA);
my $user_id = 0;

if ($dbh && $dbp) {
  $user_id = getUserIdByName($dbh, $user);          # Defined on sm_user.pl
  if ($user_id > 0) {
    showPdaTools($user_id, $sess_code);
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
  my ($user_id, $sess_code) = @_;
  my ($ok, $msg, $user_cookie, %user_info);

  if (sessionExist($dbp, $user_id, $sess_code)) {       # Defined on sm_webenv.pl
    #-- Set cookie for logon user --#
    $user_info{'SESS_CODE'} = $sess_code;
    #$user_cookie = cookie(-name => $COOKIE_PDA, -value => \%user_info, -path => '/', -expires => '+2d', -secure => 1);  
    $user_cookie = CGI::Cookie->new(-name => $COOKIE_PDA, -value => \%user_info, -path => '/', -expires => '+2d', -secure => 1, -httponly => 1);
    print header(-type => 'text/html', -charset => 'utf-8', -cookie => $user_cookie);
    $PRINTHEAD = 1;
  
    #-- Then go to the first page of PDA tools --#
    redirectTo("/cgi-pl/tools/select_tools.pl");        
  }
  else {
    print header(-type=>'text/html', -charset=>'utf-8');
    alert("Unable to create session, please login again");
    redirectTo("/cgi-pl/index.pl");
  }
}
