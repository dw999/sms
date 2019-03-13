#!/usr/bin/perl

##########################################################################################
# Program: /www/itnews/cgi-pl/auth/logon_agent.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-31      AY              Help to login to the messaging system. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use URI::Escape;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $PRINTHEAD;

my $token = allTrim(uri_escape(paramAntiXSS('tk')));       # Authentication token. Note: Perl CGI parameters receiving function unescape passed data automatically.

my $dbh = dbconnect($COOKIE_MSG);

if ($dbh) {
  my $user_id = getUserIdFromToken($dbh, $token);          # Defined on sm_user.pl. Only a token with status 'R' will be accepted. It prevents attacker to get in the system by using old token.
  if ($user_id > 0) {
    setLoginTokenUsed($dbh, $token);                       # Defined on sm_user.pl. Set token status to 'U' now.
    _setUserInformFlag($dbh, $user_id, 1);                 # Defined on sm_msglib.pl. Reset new message inform flag to 1. i.e. Accept new message inform.
    deleteUserInformRecord($dbh, $user_id);                # Defined on sm_msglib.pl
    goLogonProcess($user_id);
  }
  else {
    my $url = selectSiteForVisitor($dbh);                  # Defined on sm_webenv.pl
    print header(-type=>'text/html', -charset=>'utf-8');
    redirectTo($url);
  }  
}
else {
  print header(-type=>'text/html', -charset=>'utf-8');
  redirectTo("https://www.microsoft.com");
}


sub goLogonProcess {
  my ($user_id) = @_;
  my ($ok, $msg, $sess_code, $user_cookie, $site_dns, %user_info);

  ($ok, $msg, $sess_code) = createSessionRecord($dbh, $user_id);      # Defined on sm_webenv.pl
  if ($ok) {
    #-- Set cookie for logon user --#
    $user_info{'SESS_CODE'} = $sess_code;
    $user_cookie = cookie(-name => $COOKIE_MSG, -value => \%user_info, -path => '/', -expires => '+2d', -secure => 1);  
    print header(-charset => 'utf-8', -cookie => $user_cookie);
    $PRINTHEAD = 1;
    
    #-- Then go to the first page of messaging --#
    redirectTo("/cgi-pl/msg/message.pl");          
  }  
  else {
    $site_dns = getSiteDNS($dbh, 'D');                                # Defined on sm_webenv.pl
    alert("Unable to create session, please login again");
    redirectTo("$site_dns/cgi-pl/index.pl");    
  }
}

