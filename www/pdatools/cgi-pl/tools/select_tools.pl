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
# Program: /www/pdatools/cgi-pl/tools/select_tools.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-01      DW              Select PDA tool option. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;
our $COOKIE_MSG;
our $PDA_BG_COLOR;

my $dbh = dbconnect($COOKIE_PDA);
my $dbx = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_PDA);                               # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $user_role = getUserRole($dbx, $user_id);                          # Defined on sm_user.pl. Note: user list on msgdb only. 
my @features = getFeatures($dbh);

printJavascriptSection();
printSelectToolsForm();

dbclose($dbh);
dbclose($dbx);
#-- End Main Section --#


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  
  <script>
    function runFeature(url) {
      window.location.href = url;
    }
  </script>
__JS
}


sub getFeatures {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT b.feature_url, b.feature_icon, a.list_order
    FROM feature_list a, feature_store b
    WHERE a.feature_id = b.feature_id
    ORDER BY a.list_order
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'url' => $data[0], 'icon' => $data[1]};
    }    
  }
  $sth->finish;
  
  return @result;
}


sub printSelectToolsForm {
	my ($html, $company_name, $copy_right, $spaces, $panel, $panel_btn);

  $company_name = getDecoyCompanyName();      # Defined on sm_webenv.pl
  $copy_right = getDecoySiteCopyRight();      # Defined on sm_webenv.pl
  $spaces = '&nbsp;' x 2; 
  
  #-- If login user is system administrator, then he/she has right to maintain decoy site settings. --#
  if ($user_role == 2) {
    $panel = <<__HTML;
    <div data-role="panel" data-position-fixed="true" data-position="left" data-display="overlay" id="setup">
      <div data-role="main" class="ui-content">
        <ul data-role="listview">
          <li data-role="list-divider" style="color:darkgreen;">System Administration</li>
          <li><a href="/cgi-pl/admin/feature_setup.pl" data-ajax="false">Feature Setup</a></li>
        </ul>
      </div>
    </div>  
__HTML

    $panel_btn = <<__HTML;
    <a href="#setup" data-icon="bars" class="ui-btn-left">Setup</a>
__HTML
  }
  else {
    $panel = $panel_btn = '';
  }
    
	#-- Important: 'data-ajax="false"' must be set for links with dynamic content. Otherwise, unexpected result such as invalid javascript --#
	#--            content and expired passed parameters value will be obtained.                                                           --#
  $html = <<__HTML;
	<div data-role="page" id="mainpage" style="background-color:$PDA_BG_COLOR">
    $panel
    
	  <div data-role="header" style="overflow:hidden;" data-position="fixed">
      $panel_btn
			<h1>$company_name</h1>
			<a href="/cgi-pl/auth/logout.pl" data-icon="power" class="ui-btn-right" data-ajax="false">Quit</a>					
		</div>	

		<div data-role="main" class="ui-body-d ui-content">
__HTML
  
  foreach my $rec (@features) {
    my $this_url = $rec->{'url'};
    my $this_icon = $rec->{'icon'};
    
    $html .= <<__HTML;
      <img src="$this_icon" height="100px" onClick="runFeature('$this_url');">
      $spaces
__HTML
  }
  
  $html .= <<__HTML;
    <div data-role="footer" data-position="fixed">
      <table width="100%" cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr><td align=center><font size="2px">$copy_right</font></td></tr>
      </tbody>
      </table>
    </div> 
  </div>
__HTML

  print $html;
}
