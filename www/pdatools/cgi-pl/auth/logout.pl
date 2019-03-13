#!/usr/bin/perl

##########################################################################################
# Program: /www/pdatools/cgi-pl/auth/logout.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-07-23      AY              Logout the decoy web site. 
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

