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
# Program: /www/itnews/cgi-pl/admin/maintain_decoy_sites.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-05      AY              Maintain a list of decoy sites which are used
#                                               to redirect intruders away from the messaging
#                                               site.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $op = paramAntiXSS('op');                               # A = Add, E = Edit, D = Delete.
my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $site_url_old = paramAntiXSS('site_url_old');           # Original decoy site URL. It is used for decoy site amendment operation.
my $site_url = paramAntiXSS('site_url');                   # Decoy site URL.
my $key_words = paramAntiXSS('key_words');                 # Categorization Key words of the decoy site.

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @site_list = ();
my %decoy_site;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {
  if ($op eq 'A') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = addNewDecoySite($dbh, $site_url, $key_words);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_decoy_sites.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_decoy_sites.pl?op=A");
      }        
    }
    else {
      printNewDecoySiteForm();
    }
  }
  elsif ($op eq 'E') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = modifyDecoySite($dbh, $site_url_old, $site_url, $key_words);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_decoy_sites.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_decoy_sites.pl?op=E");
      }        
    }
    else {
      %decoy_site = getDecoySiteDetails($dbh, $site_url);
      printDecoySiteEditForm(\%decoy_site);
    }  
  }
  elsif ($op eq 'D') {
    my ($ok, $msg) = deleteDecoySite($dbh, $site_url);
    if (!$ok) {
      alert($msg);
    }  
    redirectTo("/cgi-pl/admin/maintain_decoy_sites.pl");
  }
  else {
    @site_list = getDecoySiteList($dbh);
    printDecoySiteList(\@site_list); 
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
    
    function addDecoySite() {
      document.getElementById("op").value = "A";
      document.getElementById("frm_decoy_site").submit();          
    }
    
    function editDecoySite(site_url) {
      document.getElementById("op").value = "E";
      document.getElementById("site_url").value = site_url;
      document.getElementById("frm_decoy_site").submit();      
    }
    
    function deleteDecoySite(site_url) {
      if (confirm("Are you sure to delete this decoy site?")) {
        document.getElementById("op").value = "D";
        document.getElementById("site_url").value = site_url;
        document.getElementById("frm_decoy_site").submit();
      }
    }
    
    function saveDecoySite() {
      var site_url = allTrim(\$('#site_url').val());
      
      if (site_url == "") {
        alert("Please input decoy site URL before saving");
        \$('#site_url').focus();
        return false;
      }
            
      \$('#oper_mode').val("S");
      \$('#frm_decoy_site').submit();      
    }
  </script>
__JS
}


sub isHeSysAdmin {
  my ($dbh, $user_id) = @_;
  my ($role, $result);
  
  $role = getUserRole($dbh, $user_id);               # Defined on sm_user.pl
  $result = ($role == 2)? 1 : 0;
  
  return $result;
}


sub addNewDecoySite {
  my ($dbh, $site_url, $key_words) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  if (isDecoySiteExist($dbh, $site_url)) {
    ($ok, $msg) = updateDecoySite($dbh, $site_url, $site_url, $key_words);  
  }
  else {
    $sql = <<__SQL;
    INSERT INTO decoy_sites
    (site_url, key_words)
    VALUES
    (?, ?)    
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($site_url, $key_words)) {
      $msg = "Unable to add decoy site $site_url. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;    
  }
  
  return ($ok, $msg);  
}


sub isDecoySiteExist {
  my ($dbh, $site_url) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT COUNT(*) AS cnt
    FROM decoy_site
    WHERE site_url = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($site_url)) {
    ($cnt) = $sth->fetchrow_array();
    $result = ($cnt > 0)? 1 : 0;
  }
  else {
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub printNewDecoySiteForm {
  my ($html);
  
  $html = <<__HTML;
  <form id="frm_decoy_site" name="frm_decoy_site" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="/cgi-pl/admin/maintain_decoy_sites.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Add Decoy Site</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <label for="site_url">Decoy Site URL:</label>
      <input type="text" id="site_url" name="site_url" value="$site_url" maxlength=512>
      <label for="key_words">Site Categorization Key Words:</label>
      <input type="text" id="key_words" name="key_words" value="$key_words" maxlength=512 placeholder="Key words like 'Tech News', 'Forum', etc.">
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveDecoySite();">
      <br>
      <b>Remark:</b><br>
      You may input multiple key words by seperating them with comma.
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub modifyDecoySite {
  my ($dbh, $site_url_old, $site_url, $key_words) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  $site_url = allTrim($site_url);
  $site_url_old = allTrim($site_url_old);
  
  if ($site_url eq $site_url_old) {
    #-- In this case, decoy site URL is remain the same. --#
    ($ok, $msg) = updateDecoySite($dbh, $site_url_old, $site_url, $key_words);
  }
  else {
    if (isDecoySiteExist($dbh, $site_url)) {
      if (startTransaction($dbh)) {
        ($ok, $msg) = deleteDecoySite($dbh, $site_url_old);
        
        if ($ok) {
          ($ok, $msg) = updateDecoySite($dbh, $site_url, $site_url, $key_words);  
        }
        
        if ($ok) {
          commitTransaction($dbh);
        }
        else {
          rollbackTransaction($dbh);
        }
      }
      else {
        $msg = "Unable to start SQL transaction session, the decoy site can't be updated.";
        $ok = 0;
      }
    }
    else {
      #-- In this case, decoy site URL is changed. --#
      ($ok, $msg) = updateDecoySite($dbh, $site_url_old, $site_url, $key_words);  
    }
  }
  
  return ($ok, $msg);
}


sub updateDecoySite {
  my ($dbh, $site_url_old, $site_url, $key_words) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE decoy_sites
    SET site_url = ?,
        key_words = ?
    WHERE site_url = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($site_url, $key_words, $site_url_old)) {
    $msg = "Unable to update decoy site $site_url_old. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getDecoySiteDetails {
  my ($dbh, $site_url) = @_;
  my ($sql, $sth, $key_words, %result);
  
  $sql = <<__SQL;
  SELECT key_words
    FROM decoy_sites
    WHERE site_url = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($site_url)) {
    ($key_words) = $sth->fetchrow_array();
    %result = ('site_url' => $site_url, 'key_words' => $key_words);
  }
  
  return %result;
}


sub printDecoySiteEditForm {
  my ($decoy_site_ref) = @_;
  my ($html, %decoy_site);

  %decoy_site = %$decoy_site_ref;
  
  $html = <<__HTML;
  <form id="frm_decoy_site" name="frm_decoy_site" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="site_url_old" name="site_url_old" value="$decoy_site{'site_url'}">
  
	<div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="/cgi-pl/admin/maintain_decoy_sites.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>			
		  <h1>Edit Decoy Site</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">
      <label for="site_url">Decoy Site URL:</label>
      <input type="text" id="site_url" name="site_url" value="$decoy_site{'site_url'}" maxlength=512>
      <label for="key_words">Site Categorization Key Words:</label>
      <input type="text" id="key_words" name="key_words" value="$decoy_site{'key_words'}" maxlength=512 placeholder="Key words like 'Tech News', 'Forum', etc.">
      <br>
      <input type="button" id="save" name="save" value="Save" onClick="saveDecoySite();">
      <br>
      <b>Remark:</b><br>
      You may input multiple key words by seperating them with comma.
    </div>    
  </div>
  </form>
__HTML
  
  print $html;
}


sub deleteDecoySite {
  my ($dbh, $site_url) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM decoy_sites
    WHERE site_url = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($site_url)) {
    $msg = "Unable to delete decoy site $site_url. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getDecoySiteList {
  my ($dbh) = @_;
  my ($sql, $sth, @result);  

  $sql = <<__SQL;
  SELECT site_url
    FROM decoy_sites
    ORDER BY site_url
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my ($this_site_url) = $sth->fetchrow_array()) {
      push @result, $this_site_url;
    }    
  }
  $sth->finish;
  
  return @result;
}


sub printDecoySiteList {
  my ($site_list_ref) = @_;
  my ($html, @site_list);
  
  @site_list = @$site_list_ref;
  
  $html = <<__HTML;
  <form id="frm_decoy_site" name="frm_decoy_site" action="" method="post">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="site_url" name="site_url" value="">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack()" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Decoy Sites</h1>
      <a href="javascript:goHome()" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed;">
      <thead>
        <tr style="background-color:lightblue">
          <td width=80% align=center valign=center><b>Decoy Site</b></td>
          <td align=center valign=center><b>Delete</b></td>
        </tr>
      </thead>      
      <tbody>
__HTML

  foreach my $this_site_url (@site_list) {
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td valign=center style="word-wrap:break-word;"><a href="javascript:editDecoySite('$this_site_url')">$this_site_url</a></td>
          <td align=center valign=center><input type=button id="del_ds" name="del_ds" data-icon="delete" data-iconpos="notext" onClick="deleteDecoySite('$this_site_url')"></td>
        </tr>
__HTML
  }

  $html .= <<__HTML;
        <tr style="background-color:lightblue">
          <td colspan=2 align=center>End</td>
        </tr>
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center valign=center><input type=button id="add_ds" name="add_ds" value="Add Decoy Site" data-icon="plus" onClick="addDecoySite()"></td>
        </tr> 
      </tbody>
      </table>
    </div>        
  </div>
  </form>
__HTML
  
  print $html;
}

