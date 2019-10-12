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
# Program: /www/itnews/cgi-pl/admin/maintain_main_sites.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-09-28      DW              Maintain decoy login site and message site.
# V1.0.01       2019-10-12      DW              Function 'isHeSysAdmin' is moved to sm_user.pl
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $decoy_site = allTrim(paramAntiXSS('decoy_site'));      # Login (decoy) site DNS name.
my $message_site = allTrim(paramAntiXSS('message_site'));  # Messaging site DNS name.

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my %main_sites;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl
  if ($oper_mode eq 'S') {
    my ($ok, $msg) = saveMainSites($dbh);
    if ($ok) {
      redirectTo("/cgi-pl/admin/system_setup.pl");
    }
    else {
      alert($msg);
      back();
    }    
  }
  else {
    %main_sites = getMainSites($dbh);
    printMainSitesForm();
  }  
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. --#
  redirectTo("/cgi-pl/admin/system_setup.pl");    
}

dbclose($dbh);
#-- End Main Section --#


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>

  <script>
    function goBack() {
      window.location.href = "/cgi-pl/admin/system_setup.pl";
    }
  
    function goHome() {
      window.location.href = "/cgi-pl/msg/message.pl";
    }
    
    function saveMainSites() {
      var the_decoy_site = allTrim(document.getElementById("decoy_site").value);
      var the_message_site = allTrim(document.getElementById("message_site").value);
      
      if (the_decoy_site == "") {
        alert("Login (decoy) site DNS name should not be blank");
        return false;
      }
      
      if (the_message_site == "") {
        alert("Messaging site DNS name should not be blank");
        return false;
      }
      
      document.getElementById("oper_mode").value = "S";
      document.getElementById("frm_main_sites").submit();
    }
  </script>
__JS
}


sub saveMainSites {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = removeSites($dbh);
    
    if ($ok) {
      ($ok, $msg) = addSite($dbh, $decoy_site, 'DECOY');
    }
    
    if ($ok) {
      ($ok, $msg) = addSite($dbh, $message_site, 'MESSAGE');
    }
   
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "Unable to start SQL transaction, main sites can't be updated.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub removeSites {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM sites 
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to clear old sites settings. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub addSite {
  my ($dbh, $site_dns, $site_type) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO sites
  (site_type, site_dns, status)
  VALUES
  (?, ?, 'A')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($site_type, $site_dns)) {
    $msg = "Unable to save site DNS name ($site_type). Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getMainSites {
  my ($dbh) = @_;
  my ($sql, $sth, $decoy_site_dns, $message_site_dns, %result);
  
  $sql = <<__SQL;
  SELECT site_type, site_dns
    FROM sites
    WHERE status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      if (uc($data[0]) eq 'DECOY') {
        $decoy_site_dns = $data[1];
      }
      elsif (uc($data[0]) eq 'MESSAGE') {
        $message_site_dns = $data[1];
      }
    }    
  }
  $sth->finish;
  
  %result = ('decoy_site' => $decoy_site_dns, 'message_site' => $message_site_dns);
  
  return %result;
}


sub printMainSitesForm {
  my ($html, $decoy_site_dns, $message_site_dns);
  
  $decoy_site_dns = ($decoy_site eq '')? $main_sites{'decoy_site'} : $decoy_site;
  $message_site_dns = ($message_site eq '')? $main_sites{'message_site'} : $message_site;
  
  $html = <<__HTML;
  <form id="frm_main_sites" name="frm_main_sites" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="javascript:goBack();" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Main Sites</h1>
      <a href="javascript:goHome();" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>      
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <label for="decoy_site">Login (Decoy) Site DNS name:</label>
      <input type="text" id="decoy_site" name="decoy_site" value="$decoy_site_dns">
      <label for="message_site">Messaging Site DNS name:</label>
      <input type="text" id="message_site" name="message_site" value="$message_site_dns">      
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveMainSites();">                  
    </div>
  </div>
  </form>
__HTML

  print $html  
}

