#!/usr/bin/perl

##########################################################################################
# Program: /www/pdatools/cgi-pl/index.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-04-02      AY              Starting page of PDA Tools.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";

my $url = allTrim(paramAntiXSS('url'));

print header(-type=>'text/html', -charset=>'utf-8');

if ($url eq '') {
  my $params = joinPassParameters();     # There are 10 arbitary parameters for 'login.pl', from 'para0' to 'para9'.
  redirectTo("/cgi-pl/auth/login.pl?$params");
}


sub joinPassParameters {
  my ($result, @buffer);
  
  $result = '';
  
  for (my $i = 0; $i <= 9; $i++) {
    my $this_param = "para$i";
    my $this_var = allTrim(paramAntiXSS($this_param));
    
    if ($this_var ne '') {
      push @buffer, "$this_param=$this_var";
    }
  }

  if (scalar(@buffer) > 0) {
    $result = join('&', @buffer);
  }
  
  return $result;
}


