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
# Program: /www/itnews/cgi-pl/read_news.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-30      DW              Authenticate visitor 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use URI::Escape;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;

print header(-type=>'text/html', -charset=>'utf-8');

my $token = allTrim(uri_escape(paramAntiXSS('tk')));    # Authentication token. Note: Perl CGI parameters receiving function unescape passed data automatically.

my $dbh = dbconnect($COOKIE_MSG);
my $url = '';

if ($dbh) {
  if (isTokenValid($dbh, $token)) {                     # Defined on sm_user.pl
    $url = "/cgi-pl/auth/logon_agent.pl?tk=$token";
    redirectTo($url);
  }
  else {
    $url = selectSiteForVisitor($dbh);                  # Defined on sm_webenv.pl
  
    if (allTrim($url) ne '') {
      redirectTo($url);
    }
    else {
      redirectTo("https://www.microsoft.com");
    }
  }  
  dbclose($dbh);
}
else {
  redirectTo("https://www.microsoft.com");
}

