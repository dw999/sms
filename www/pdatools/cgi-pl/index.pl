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
# Program: /www/pdatools/cgi-pl/index.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-04-02      DW              Starting page of PDA Tools.
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


