#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/auth/logout.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-19      AY              Logout the messaging system.
# V1.0.01       2018-08-21      AY              Go to login page as logout.
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
