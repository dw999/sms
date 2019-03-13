#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/index.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-30      AY              Act as decoy page to protect the site.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;                                      # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);
my $url = "";

print header(-type=>'text/html', -charset=>'utf-8');

if ($dbh) {
  $url = selectSiteForVisitor($dbh);       # Defined on sm_webenv.pl
  
  if (allTrim($url) ne '') {
    redirectTo($url);
  }
  else {
    redirectTo("https://www.microsoft.com");
  }
  
  dbclose($dbh);
}
else {
  redirectTo("https://www.microsoft.com");
}


