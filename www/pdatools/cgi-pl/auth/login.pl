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
# Program: /www/pdatools/cgi-pl/auth/login.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-18      DW              Login to the system.
# V1.0.01       2018-10-12      DW              - Hide 'Join Us' link if connection_mode is
#                                                 1.
#                                               - Redirect user to messaging page if connection_mode
#                                                 is 1.
# V1.0.02       2019-01-07      DW              - Hide 'Join Us' link if connection_mode is
#                                                 1 or 3.
#                                               - Redirect user to messaging page if connection_mode
#                                                 is 1 or 2.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                      # Both are defined on sm_webenv.pl
our $COOKIE_MSG;                                  

my $oper_mode = allTrim(paramAntiXSS('oper_mode'));   # 'A' = Authenticate, 'N' = Request to join, others go to login screen.
my $user = allTrim(paramAntiXSS('user'));             # User name.
my $pass = allTrim(paramAntiXSS('pass'));             # Password.
my $latitude = paramAntiXSS('latitude') + 0;
my $longitude = paramAntiXSS('longitude') + 0;

my $dbm = dbconnect($COOKIE_MSG);

print header(-type=>'text/html', -charset=>'utf-8');

if ($oper_mode eq 'A') {
  my ($status, $message, $home_page_url) = authenticateLoginUser($user, $pass, $latitude, $longitude);      # Defined on sm_user.pl     
  
  if ($status == 1) {    
    redirectTo("$home_page_url");
  }
  else {
    alert($message);
    redirectTo("/cgi-pl/auth/login.pl?user=$user");
  }
}
elsif ($oper_mode eq 'N') {
  redirectTo("/cgi-pl/auth/request_to_join.pl");
}
else {
  printJavascriptSection();
  printLoginPage();
}
#-- End Main Section --#


sub printJavascriptSection {
  print <<__JS;
  <script type="text/javascript">
    function onPositionUpdate(position) {
      var lat = position.coords.latitude;
      var lng = position.coords.longitude;
      
      document.getElementById("latitude").value = lat;
      document.getElementById("longitude").value = lng;
    }    
    
    function doLogin() {
      var username = document.getElementById("user").value;
    
      if (username != "") {
        if (navigator.geolocation) {
          navigator.geolocation.getCurrentPosition(onPositionUpdate);
        }      
        document.getElementById("oper_mode").value = "A";
        document.getElementById("frmlogin").submit();
      }
      else {
        alert("Please input username and password to login to the system.");
      }
    }
    
    function requestToJoin() {
      document.getElementById("oper_mode").value = "N";
      document.getElementById("frmlogin").submit();    
    }
  </script>
__JS
}


sub printLoginPage {
  my ($company_name, $html, $title, $foot, $comp_logo, $device_type, $font_size, $scale, $connect_mode, $join_us_link, %options);
  
  ($device_type) = detectClientDevice();                             # Defined on sm_webenv.pl
  $font_size = ($device_type eq 'desktop')? '2' : '5';
  $scale = ($device_type eq 'desktop')? '1.0' : '0.45';
  $options{'oper_mode'} = 'S';
  $company_name = getDecoyCompanyName();                             # Defined on sm_webenv.pl
  $title = "<span class='title1'><h2>$company_name</h2></span>";
  $connect_mode = getSysSettingValue($dbm, 'connection_mode') + 0;
  
  if ($connect_mode == 0 || $connect_mode == 2) {
    $join_us_link = <<__HTML;
    <tr>
      <td colspan=3 align=center class=t_text><a href="#" onClick="requestToJoin();"><b>Join Us</b></a></td>
    </tr>
__HTML
  }
  else {
    $join_us_link = '';
  }
  
  $html = <<__HTML;
  <html>
  <head>
    <title>Logon Page</title>
    <meta name="viewport" content="width=device-width, initial-scale=$scale">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <script src="/js/jquery.min.js"></script>
    
    <style>
      div#div2	{background-color: lightblue; padding: 10;}
      div#outer	{float: center; background: #A9A9A9; padding: 2px; width: 100%;}
    </style>
    
    <script type="text/javascript"> 
      \$(document).ready(function() {
        \$('#user').focus();
      })
    </script>    
__HTML

  $html .= printCSS($COOKIE_PDA, \%options);         # Defined on sm_webenv.pl
  
  $html .= <<__HTML;
  </head>
  
  <body leftmargin=0 topmargin=0 marginwidth=0 marginheight=0>
  <center>
  <table cellpadding=0 cellspacing=0 height=100% border=0>
  <tr>
    <td valign=center align=center>
      <div id="outer">
        <div id="div2">
          $title
          <br>
          <br>
          <form id="frmlogin" name="frmlogin" action="" method="post">
          <input type=hidden id="oper_mode" name="oper_mode" value="">
          <input type=hidden id="latitude" name="latitude" value="0">
          <input type=hidden id="longitude" name="longitude" value="0">
  
          <table width=300>
	        <tr>
		        <td class=t_text>Username</td>
		        <td><input type=text size=15 id="user" name="user" value='$user'></td>
		        <td></td>
	        </tr>
	        <tr>
		        <td class=t_text>Password</td>
		        <td><input type=password size=15 id="pass" name="pass"></td>
		        <td></td>
	        </tr>
          <tr>
	          <td colspan=3>&nbsp;</td>
          </tr>          
	        <tr>
		        <td colspan=3 align=center><input type=button value=" Login " onClick="doLogin();"></td>
          </tr>
          <tr>
	          <td colspan=3>&nbsp;</td>
          </tr>
          <tr>
	          <td colspan=3>&nbsp;</td>
          </tr>
          $join_us_link
          </table>
          </form>
        </div>
      </div>
    </td>
  </tr>
  </table>
  </center>
  </body>
  </html>
__HTML

  print $html; 
}

