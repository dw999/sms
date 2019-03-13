#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/read_news.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-30      AY              Authenticate visitor 
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

