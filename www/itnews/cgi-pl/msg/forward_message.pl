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
# Program: /www/itnews/cgi-pl/msg/forward_message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-08-14      AY              Forward message to another group.
# V1.0.01       2018-08-21      AY              Let user input additional message as forward
#                                               a message.
# V1.0.02       2018-08-29      AY              If a to-be-forward message with attached file, 
#                                               make a new copy of that file for the forwarded
#                                               message.
# V1.0.03       2018-09-21      AY              Take care message loading on demand by passing the ID of
#                                               the first load message to the calling program. Note: this
#                                               data is stored on local storage of the web browser.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
use File::Copy;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $ITN_TN_PATH;                                          # Defined on sm_webenv.pl

my $oper_mode = paramAntiXSS('oper_mode');                 # 'S' = Save, others show message groups selection page.
my $from_group_id = paramAntiXSS('from_group_id') + 0;     # Group ID of message forwarded from
my $to_group_id = paramAntiXSS('to_group_id') + 0;         # Group ID of message forwarded to
my $msg_id = paramAntiXSS('msg_id') + 0;                   # ID of the message to be forwarded
my $a_message = paramAntiXSS('a_message');                 # Additional message 

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;

my $ok = 1;
my $msg = '';
my %fw_message = ();

printJavascriptSection();

if ($oper_mode eq 'S') {
  ($ok, $msg, %fw_message) = getForwardMessageDetails($dbh, $msg_id);
  if ($ok) {
    ($ok, $msg) = forwardMessage($dbh, $user_id, $to_group_id, $a_message, \%fw_message);
    if ($ok) {
      if ($from_group_id == $to_group_id) {
        returnToCaller($to_group_id);
      }
      else {
        clearLocalData();
        redirectTo("/cgi-pl/msg/do_sms.pl?g_id=$to_group_id");
      }
    }
    else {
      alert($msg);
      returnToCaller($from_group_id);
    }    
  }
  else {
    alert($msg);
    returnToCaller($from_group_id);
  }
}
else {
  my @groups = getGroupsCouldBeForwarded($dbh, $user_id);
  printStyleSection();
  printGroupSelectionForm($from_group_id, \@groups);  
}

dbclose($dbh);
#-- End Main Section --#


sub printJavascriptSection {
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    function forwardMessage() {
      var value = parseInt(\$('input[name=to_group_id]:checked', '#frm_forward').val(), 10);
      if (isNaN(value)) {
        alert("Please select a group to let message forward to");
      }
      else {
        document.getElementById("oper_mode").value = "S";
        document.getElementById("frm_forward").submit();
      }
    }
    
    function goBack(from_group_id) {
      var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
      var f_m_id = (is_iOS == false)? getLocalStoredItem("m_id") : Cookies.get("m_id");         // Defined on common_lib.js : js.cookie.min.js
      var top_id = (is_iOS == false)? getLocalStoredItem("top_id") : Cookies.get("top_id");
      window.location.href = "/cgi-pl/msg/do_sms.pl?g_id=" + from_group_id + "&f_m_id=" + f_m_id + "&top_id=" + top_id;
    }
  </script>
__JS
}


sub returnToCaller {
  my ($group_id) = @_;
 
  print <<__JS;
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script> 
  
  <script>
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
    var f_m_id = (is_iOS == false)? getLocalStoredItem("m_id") : Cookies.get("m_id");        // Defined on common_lib.js : js.cookie.min.js
    var top_id = (is_iOS == false)? getLocalStoredItem("top_id") : Cookies.get("top_id");
    window.location.href = "/cgi-pl/msg/do_sms.pl?g_id=$group_id&f_m_id=" + f_m_id + "&top_id=" + top_id;
  </script>
__JS
}


sub clearLocalData {
  print <<__JS;
  <script src="/js/js.cookie.min.js"></script>
  <script src="/js/common_lib.js"></script>
  
  <script>
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);
    
    if (is_iOS) {
      Cookies.remove("g_id");                                    // Defined on js.cookie.min.js
      Cookies.remove("u_id");
      Cookies.remove("m_id");
      Cookies.remove("top_id");
    }
    else {
      deleteLocalStoredItem("g_id");                             // Defined on common_lib.js
      deleteLocalStoredItem("u_id");                             
      deleteLocalStoredItem("m_id");                             
      deleteLocalStoredItem("top_id");                                   
    }
  </script>
__JS
}


sub getForwardMessageDetails {
  my ($dbh, $msg_id) = @_;
  my ($ok, $msg, $sql, $sth, %result);

  $ok = 1;
  $msg = '';
  %result = ();
  
  $sql = <<__SQL;
  SELECT a.sender_id, a.msg, a.fileloc, b.encrypt_key
    FROM message a, msg_group b
    WHERE a.group_id = b.group_id
      AND a.msg_id = ? 
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($msg_id)) {
    my @data = $sth->fetchrow_array();
    my $sender_id = $data[0] + 0;
    my $encrypted_msg = $data[1];
    my $fileloc = $data[2];
    my $key = $data[3];
    #-- Need to get decrypted content of the message to be forwarded --#
    my ($ok, $message) = _decrypt_str($encrypted_msg, $key);                        # Defined on sm_user.pl
    
    if ($ok) {
      %result = ('sender_id' => $sender_id, 'message' => $message, 'fileloc' => $fileloc);  
    }
    else {
      $msg = "Unable to decrypt forward message";
    }
  }
  else {
    $msg = "Unable to get forward message details. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg, %result);
}


sub forwardMessage {
  my ($dbh, $user_id, $to_group_id, $a_message, $fw_message_ref) = @_;
  my ($ok, $msg, $op_flag, $op_user_id, $message, $fileloc, $fw_fileloc, %fw_message);
  
  $ok = 1;
  $msg = '';
  $fw_fileloc = '';
  
  %fw_message = %$fw_message_ref;
  $op_flag = 'F';
  $op_user_id = $fw_message{'sender_id'};
  $message = $fw_message{'message'};
  $fileloc = allTrim($fw_message{'fileloc'});
  $a_message = allTrim($a_message);
  
  if ($fileloc ne '') {
    #-- When a message with attached file is forwarded, then the attached file must be copied as a new file for message forwarding. --#
    #-- Otherwise, it would be lost in the forwarded message if the original message is deleted.                                    --#              
    ($ok, $msg, $fw_fileloc) = copyForwardFile($fileloc); 
  }
  
  if ($ok) { 
    ($ok, $msg) = sendMessage($dbh, $user_id, $to_group_id, $message, $fw_fileloc, $op_flag, $op_user_id);       # Defined on sm_msglib.pl
    if ($ok && $a_message ne '') {
      ($ok, $msg) = sendMessage($dbh, $user_id, $to_group_id, $a_message, '', '', 0); 
    }
  }
  
  return ($ok, $msg);
}


sub copyForwardFile {
  my ($fileloc) = @_;
  my ($ok, $msg, $filename, $dirs, $suffix, $fw_fileloc, $tn_file, $fw_tn_file, $idx, $stop_run);
  
  $ok = 1;
  $msg = $fw_fileloc = '';
  
  ($filename, $dirs, $suffix) = fileNameParser($fileloc);     # Defined on sm_webenv.pl
  $tn_file = "$ITN_TN_PATH/$filename.jpg";
  if (!(-f $tn_file)) {
    $tn_file = '';
  }
  
  $idx = 1;
  $stop_run = 0;
  while (!$stop_run) {
    my $ver_no = sprintf("%03d", $idx);
    $fw_fileloc = "$dirs$filename-$ver_no$suffix";
    $fw_tn_file = ($tn_file ne '')? "$ITN_TN_PATH/$filename-$ver_no.jpg" : "";        # Note: Thumbnail file may not exist.
    
    if (!(-f $fw_fileloc)) {
      $stop_run = 1;
    }
    else {
      $idx++;
      if ($idx > 999) {
        #-- Last resort --#
        my $random_name = _generateRandomStr('A', 16);
        $fw_fileloc = "$dirs$random_name$suffix";
        $fw_tn_file = ($tn_file ne '')? "$ITN_TN_PATH/$random_name.jpg" : "";
        $stop_run = 1;
      }      
    }    
  }
  
  if ($fw_fileloc ne '') {
    if (!copy("$fileloc", "$fw_fileloc")) {
      $msg = "Unable to duplicate attached file of the to-be-forward message. Error: $!";
      $ok = 0;
      $fw_fileloc = '';
    }
    
    if ($fw_tn_file ne '') {
      if (!copy("$tn_file", "$fw_tn_file")) {
        $msg = "Unable to duplicate thumbnail of attached file of the to-be-forward message. Error: $!";
        $ok = 0;
      }
    }    
  }
  else {
    $msg = "By unknown reason, it is unable to determine the name of the attached file of the forwarding message.";
    $ok = 0;    
  }
  
  return ($ok, $msg, $fw_fileloc);
}


sub getGroupsCouldBeForwarded {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT a.group_id, a.group_name, a.group_type
    FROM msg_group a, group_member b
    WHERE a.group_id = b.group_id
      AND b.user_id = ?
    ORDER BY a.group_name;
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'group_id' => $data[0], 'group_name' => $data[1], 'group_type' => $data[2]};
    }    
  }
  
  return @result;
}


sub printStyleSection {
  print <<__STYLE;
  <style>
    .a_message {
      width:100%;
      height:120px;
      max-height:200px;
    }
  </style>
__STYLE
}


sub printGroupSelectionForm {
  my ($from_group_id, $groups_ref) = @_;
  my ($html, $private_group_marker, $cnt, @groups);
  
  $private_group_marker = "<img src='/images/lock.png' height='15px'>";
  @groups = @$groups_ref;
  
  $html = <<__HTML;
  <form id="frm_forward" name="frm_forward" action="" method="post">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="from_group_id" name="from_group_id" value="$from_group_id">
  <input type=hidden id="msg_id" name="msg_id" value="$msg_id">
    
  <div data-role="page">
    <div data-role="header" data-position="fixed">
		  <a href="javascript:goBack($from_group_id);" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>    
		  <h1>Forward to...</h1>
	  </div>	

    <div data-role="main" class="ui-body-d ui-content">    
      <fieldset data-role="controlgroup">
      <table width=100% cellpadding=0 cellspacing=0>
      <thead>
        <tr style="background-color:lightblue"><td align=center><b>Group</b></td></tr>
      </thead>
      <tbody>  
__HTML

  $cnt = 0;
  foreach my $rec (@groups) {
    my $this_group_id = $rec->{'group_id'};
    my $this_group_name = $rec->{'group_name'};
    my $this_group_marker = ($rec->{'group_type'} == 1)? $private_group_marker : '';

    $cnt++;    
    $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td>
          <input type="radio" id="to_group_id_$cnt" name="to_group_id" value="$this_group_id"><label for="to_group_id_$cnt">$this_group_marker$this_group_name</label>
        </td>
      </tr>
__HTML
  }
  
  $html .= <<__HTML;
      </tbody>
      </table>
      </fieldset>
      <br>
      <label for="a_message"><b>Additional message:</b></label>
      <textarea id="a_message" name="a_message" autofocus data-role="none" class="a_message"></textarea>
    </div>

    <div data-role="footer" data-position="fixed">
      <table width=100% cellpadding=0 cellspacing=0>
      <thead>
        <tr><td></td></tr>
      </thead>
      <tbody>  
      <tr>    
        <td align=center valign=center><input type="button" id="save" name="save" value="Go Forward" onClick="forwardMessage();"></td>
      </tr>
      </tbody>
      </table>
    </div>    
  </div>
  </form>
__HTML

  print $html;
}
