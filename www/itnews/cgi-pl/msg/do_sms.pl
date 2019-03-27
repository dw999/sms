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
# Program: /www/itnews/cgi-pl/msg/do_sms.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-28      DW              Do secret messaging.
# V1.0.01       2018-08-05      DW              Take appropriated action in accordance with
#                                               returned value of 'update_token'.
# V1.0.02       2018-08-08      DW              - Add auto-deletion and read-after-delete period
#                                                 setting option to private group administrator.
#                                               - Show private group indicator (a lock icon).
# V1.0.03       2018-08-11      DW              Increase height of message input box from 50px to 60px.
# V1.0.04       2018-08-27      DW              Add file upload feature (include camera snapshot
#                                               and video).
# V1.0.05       2018-08-31      DW              Add audio input.
# V1.0.06       2018-09-03      DW              Add manual inform option to group administrator.
# V2.0.00       2018-09-10      DW              - Drop iframe but use <div> for messages container. It
#                                                 combines all functions and codebase from do_sms.pl
#                                                 V1.0.06 and load_message.pl V1.0.03. Therefore,
#                                                 load_message.pl is no longer required. 
#                                               - Fix iPhone messages displaying problem.
#                                               - Make the inner part of the panel contents scroll independent
#                                                 from the main content page and avoid message page content to
#                                                 go to top as the panel is activated.
#                                               - Make page header and footer that they don't hide automatically
#                                                 as user tap the message page content.
# V2.0.01       2018-09-16      DW              Implement loading messages on demand. Load last 30 messages as enter
#                                               a group, then load previous messages as user kick on the 'Read More'
#                                               button at the top of loaded messages.
# V2.0.02       2019-03-11      DW              Add a blank line below date separation row as send a new message.
# V2.0.03       2019-03-27      DW              Set animation time of scrolling to 'page_end' object to 500ms on all places. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $group_id = paramAntiXSS('g_id') + 0;                   # Message group ID
my $f_m_id = paramAntiXSS('f_m_id') + 0;                   # The ID of the first message which has already loaded.
my $top_id = paramAntiXSS('top_id') + 0;                   # The ID of the first message of this group and this user. 

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $user_role = getUserRole($dbh, $user_id);               # User role of the messaging system. Defined on sm_user.pl
my $group_name = getMessageGroupName($dbh, $group_id);     # Defined on sm_msglib.pl
my $update_token = getMessageUpdateToken($dbh, $group_id); # Defined on sm_msglib.pl
my $group_role = getGroupRole($dbh, $group_id, $user_id);  # Defined on sm_msglib.pl
my $group_type = getGroupType($dbh, $group_id);            # Defined on sm_msglib.pl
my $rows_limit = getMessageBlockSize($dbh);                # Number of last messages will be loaded initially.
my %m_params = ('new_msg_only' => 0, 'rows_limit' => $rows_limit, 'f_m_id' => $f_m_id);
my @message = getGroupMessage($dbh, $group_id, $user_id, \%m_params);  # Defined on sm_msglib.pl

printStyleSection();
printJavascriptSection();
printMessagesForm($group_id, $group_role);

dbclose($dbh);
#-- End Main Section --#


sub getMessageBlockSize {
  my ($dbh) = @_;
  my ($block_size, $result);
  
  $block_size = getSysSettingValue($dbh, 'msg_block_size') + 0;     # Defined on sm_webenv.pl
  $result = ($block_size <= 0)? 30 : $block_size; 
  
  return $result;
}


sub printStyleSection {
  print <<__STYLE;
  <style>
    .s_message {
      width:100%;
      height:60px;
      max-height:200px;
    }
    
    .ui-panel.ui-panel-open {
      position:fixed;
    }
    
    .ui-panel-inner {
      position: absolute;
      top: 1px;
      left: 0;
      right: 0;
      bottom: 0px;
      overflow: scroll;
      -webkit-overflow-scrolling: touch;
    }    
  </style>
__STYLE
}


sub printJavascriptSection {
  my ($login_url, $message_url, $logout_url, $site_dns, $spaces, $space3, $first_msg_id, $first_msg_date, $last_msg_date);
    
  $site_dns = getSiteDNS($dbh, 'D');
  $login_url = "$site_dns/cgi-pl/index.pl";
  
  $site_dns = getSiteDNS($dbh, 'M');
  $message_url = "$site_dns/cgi-pl/msg/message.pl";
  $logout_url = "$site_dns/cgi-pl/auth/logout.pl";

  $spaces = '&nbsp;' x 8;
  $space3 = '&nbsp;' x 3;
  $first_msg_id = (scalar(@message) > 0)? $message[0]->{'msg_id'} + 0 : 0;
  $first_msg_date = (scalar(@message) > 0)? $message[0]->{'s_date'} : '';
  $last_msg_date = (scalar(@message) > 0)? $message[scalar(@message)-1]->{'s_date'} : '';

  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/js.cookie.min.js"></script>  
  <script src="/js/common_lib.js"></script>
  
  <script>
    var update_token = "$update_token";
    var scheduler_id;
    var op_flag;
    var op_user_id;
    var op_msg;
    var group_id = $group_id;
    var first_msg_id = $first_msg_id;
    var first_msg_date = "$first_msg_date";
    var last_msg_date = "$last_msg_date";
    var is_iOS = (navigator.userAgent.match(/(iPad|iPhone|iPod)/g)? true : false);

    \$(document).on("pageinit", function() {
      \$(function() {
        \$('html,body').animate({scrollTop: \$('#page_end').offset().top}, 500);
      })
    });
  
    \$(document).on("pagecreate", function() {      
      \$('#btn_msg_send').hide();
      \$('#reply_row').hide();
      \$('#file_upload').hide();
      \$('#go_camera').hide();
      \$('#go_file').hide();
      \$('#go_audio').hide();
    });

    //*-- This code block is frozen since it lets web browser on Android unable to scroll. --*//  
//    \$(document).on("pagecreate", function() {
//      //*-- It stops Chrome auto-reload after move to the top of the message list, may be I can get the iframe on top event to --*//
//      //*-- load more previous messages.                                                                                       --*// 
//      var scrollPosition = [
//            self.pageXOffset || document.documentElement.scrollLeft || document.body.scrollLeft,
//            self.pageYOffset || document.documentElement.scrollTop  || document.body.scrollTop
//          ];
//      var html = jQuery('html'); // it would make more sense to apply this to body, but IE7 won't have that
//      html.data('scroll-position', scrollPosition);
//      html.data('previous-overflow', html.css('overflow'));
//      html.css('overflow', 'hidden');
//      window.scrollTo(scrollPosition[0], scrollPosition[1]);      
//    });
  
    \$(document).on("pagecreate", function() {
      //*-- Define event handlers for the message input textarea object --*//
      \$('#s_message').click(
        function() {                  
          \$(this).keyup();          
        }
      );
                  
      \$('#s_message').keyup(
        function() {
          var slen = \$(this).val().length;
          if (slen > 0) {            
            \$('#btn_msg_send').show();
            \$('#btn_attach_file').hide();
            \$('#btn_audio_input').hide();
          }
          else {
            \$('#btn_msg_send').hide();
            \$('#btn_attach_file').show();
            \$('#btn_audio_input').show();            
          }
        }
      );
      
      \$('#btn_msg_send').on("click", function(event){
        if (\$(this).is("[disabled]")) {
          event.preventDefault();
        }
      });      
    });
    
    \$(document).on("pageshow", function(event) {
      runScheduler();
    });
    
    //*-- Store initial values on local storage of the web browser --*//
    if (is_iOS) {
      //*-- iOS behavior is different from other platforms, so that it needs to put cross pages data to cookie as work-around. --*//
      Cookies.set("g_id", "$group_id", {expires: 1});              // Defined on js.cookie.min.js    
      Cookies.set("u_id", "$user_id", {expires: 1});
      Cookies.set("m_id", first_msg_id, {expires: 1});
    }
    else {
      setLocalStoredItem("g_id", "$group_id");                     // Defined on common_lib.js
      setLocalStoredItem("u_id", "$user_id");
      setLocalStoredItem("m_id", first_msg_id);
    }
    
    function clearLocalData() {
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
    }
    
    function logoutSMS() {
      clearLocalData();
      window.location.href = "/cgi-pl/auth/logout.pl";
    }
    
    function goHome() {
      clearLocalData();
      window.location.href = "/cgi-pl/msg/message.pl";      
    }
        
    function runScheduler() {
      scheduler_id = setInterval(checkMessage, 2000);
      
      function checkMessage() {
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/check_message_update_token.pl',
          dataType: 'html',
          data: {group_id: $group_id, user_id: $user_id},
          success: function(ret_data) {
            var result = eval('(' + ret_data + ')');      // Note: Return data in JSON format, so that 'evel' is required.
            var mg_status = result.mg_status;
            var new_token = allTrim(mg_status.update_token);
            if (update_token != new_token) {
              if (new_token == "expired") {
                //*-- Session is expired, go to login page --*//
                alert("Session expired, login again");
                window.location.href = "$login_url";                
              }
              else if (new_token == "group_deleted") {
                //*-- Message group has been deleted by someone, go to message group main page now. --*//
                loadNewMessages($group_id, $user_id, 0);
                window.location.href = "$message_url";                
              }
              else if (new_token == "user_locked") {
                //*-- User has been locked, force logout him/her immediately. --*//
                window.location.href = "$logout_url";                                
              }
              else if (new_token == "not_group_member") {
                //*-- User has been kicked from the group, redirect him/her to message group main page immediately. --*//
                window.location.href = "$message_url"; 
              }              
              else {
                //*-- If message update token has been changed, refresh message section to pull in new message(s). --*//
                loadNewMessages($group_id, $user_id, 0);
                update_token = new_token;                
              }
            }
          },
          error: function(xhr, ajaxOptions, thrownError) {
            //alert("Unable to pull in new message. Error " + xhr.status + ": " + thrownError);
          }
        });      
      }
    }
    
    function stopScheduler() {
      clearInterval(scheduler_id);
    }
    
    function sendMessage(group_id, user_id) {
      group_id = parseInt(group_id, 10);
      user_id = parseInt(user_id, 10);
    
      var ta = document.getElementById("s_message");
      
      var content = allTrim(ta.value);
      if (content.length > 0) {
        \$('#btn_msg_send').attr("disabled", "disabled");     
      
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/send_message.pl',
          dataType: 'html',
          data: {group_id: group_id, sender_id: user_id, message: content, op_flag: op_flag, op_user_id: op_user_id, op_msg: op_msg},
          success: function(ret_data) {
            var result = eval('(' + ret_data + ')');      // Note: Return data in JSON format, so that 'evel' is required.
            var mg_status = result.mg_status;
            var new_token = allTrim(mg_status.update_token);
                    
            ta.value = "";
            \$('#s_message').click();
            \$('#btn_msg_send').hide();
            \$('#btn_msg_send').removeAttr("disabled");
            \$('#btn_attach_file').show();
            \$('#btn_audio_input').show();            
            //*-- Refresh message section --*//
            loadNewMessages($group_id, $user_id, 1);
            update_token = new_token;
            noReply();
          },
          error: function(xhr, ajaxOptions, thrownError) {
            alert("Unable to send message. Error " + xhr.status + ": " + thrownError);
            \$('#btn_msg_send').removeAttr("disabled");
            noReply();
          }          
        });
      }
      else {
        alert("Empty message won't be sent");
      }
    }
    
    function quitMessageGroup(group_id, user_id) {
      if (confirm("Do you really want to exit?")) {
        var url = "/cgi-pl/msg/edit_group_profile.pl?op=5&g_id=" + group_id + "&member_id=" + user_id;
        window.location.href = url;
      }      
    }
    
    function deleteThisGroup(group_id) {
      if (confirm("Do you want to delete this message group?")) {
        if (confirm("Last chance! Really want to go?")) {
          var url = "/cgi-pl/msg/delete_group.pl?group_id=" + group_id;
          window.location.href = url;
        }
      }
    }
    
    function replyMessage(msg_id, sender_id, sender, msg_30) {
      op_flag = 'R';
      op_user_id = sender_id;
      msg_30 = msg_30.replace(/¡/g, "'");      // Note: All single quote characters on msg_30 are converted to '¡' before passed in here.
      op_msg = msg_30;
      var html = "<font color='#0081FE' size='2px'><b>" + sender + "</b></font><br>" + op_msg;
      \$('#reply_msg_area').html(html);
      \$('#reply_row').show();    
    }
    
    function noReply() {
      op_flag = '';
      op_user_id = 0;
      op_msg = '';
      \$('#reply_msg_area').html('');
      \$('#reply_row').hide();          
    }
    
    function forwardMessage(group_id, msg_id) {
      var url = "/cgi-pl/msg/forward_message.pl?from_group_id=" + group_id + "&msg_id=" + msg_id;
      window.location.href = url;
    }

    function showTextInputPanel() {
      \$('#text_send').show();
      \$('#file_upload').hide();
      \$('#go_camera').hide();
      \$('#go_file').hide();
      \$('#go_audio').hide();
    }
    
    function attachFile() {
      \$('#text_send').hide();
      \$('#file_upload').show();
      \$('#go_camera').hide();
      \$('#go_file').hide();
      \$('#go_audio').hide();
    }
    
    function openCamera() {
      \$('#text_send').hide();
      \$('#file_upload').hide();
      \$('#go_camera').show();
      \$('#go_file').hide();
      \$('#go_audio').hide();
      \$('#photo').click();
    }
    
    function selectFileToUpload() {
      \$('#text_send').hide();
      \$('#file_upload').hide();
      \$('#go_camera').hide();
      \$('#go_file').show();
      \$('#go_audio').hide();      
      \$('#ul_file').click();      
    }
    
    function sendPhoto(group_id, user_id) {
      var send_button_status = \$('#btn_send_photo').attr("disabled");
      if (send_button_status == "disabled") {
        return false;
      }
      
      var cp = document.getElementById("caption");
            
      var image_name = allTrim(\$('#photo').val());   
      if (image_name != "") {      
        var image = \$('#photo').prop('files')[0];
        var caption = \$('#caption').val();
        var form_data = new FormData();
        form_data.append('group_id', group_id);
        form_data.append('sender_id', user_id);
        form_data.append('ul_ftype', 'photo');
        form_data.append('ul_file', image);
        form_data.append('caption', caption);
        form_data.append('op_flag', op_flag);
        form_data.append('op_user_id', op_user_id);
        form_data.append('op_msg', op_msg);
        //*-- Change button image from 'send.png' to 'files_uploading.gif' --*//
        \$('#btn_send_photo').attr('src', '/images/files_uploading.gif');
        //*-- Then disable it to prevent upload a photo twice --*//
        \$('#btn_send_photo').attr("disabled", "disabled");
      
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/upload_files.pl',
          dataType: 'text',
          cache: false,
          contentType: false,
          processData: false,
          data: form_data,
          success: function(response) {
            var new_token = response;            
            //*-- Refresh message section (just load the last sent message only) --*//
            loadNewMessages($group_id, $user_id, 1);
            update_token = new_token;                        
            \$('#btn_send_photo').removeAttr("disabled");
            \$('#btn_send_photo').attr('src', '/images/send.png');
            cp.value = "";
            showTextInputPanel();
            noReply();
          },
          error: function(xhr, ajaxOptions, thrownError) {
            alert("Unable to upload photo. Error " + xhr.status + ": " + thrownError);
            \$('#btn_send_photo').removeAttr("disabled");
            \$('#btn_send_photo').attr('src', '/images/send.png');
          }                    
        });
      }
      else {
        alert("Please take a photo before click the send button");
      }
    }
    
    function sendFile(group_id, user_id) {
      var send_button_status = \$('#btn_send_file').attr("disabled");
      if (send_button_status == "disabled") {
        return false;
      }
      
      var file_name = allTrim(\$('#ul_file').val());   
      if (file_name != "") {
        var ul_file = \$('#ul_file').prop('files')[0];
        var form_data = new FormData();
        form_data.append('group_id', group_id);
        form_data.append('sender_id', user_id);
        form_data.append('ul_ftype', 'file');
        form_data.append('ul_file', ul_file);
        form_data.append('caption', '');
        form_data.append('op_flag', op_flag);
        form_data.append('op_user_id', op_user_id);
        form_data.append('op_msg', op_msg);
        //*-- Change button image from 'send.png' to 'files_uploading.gif' --*//
        \$('#btn_send_file').attr('src', '/images/files_uploading.gif');
        //*-- Then disable it to prevent upload a file twice --*//
        \$('#btn_send_file').attr("disabled", "disabled");
      
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/upload_files.pl',
          dataType: 'text',
          cache: false,
          contentType: false,
          processData: false,
          data: form_data,
          success: function(response) {
            var new_token = response;            
            //*-- Refresh message section (just load the last sent message only) --*//
            loadNewMessages($group_id, $user_id, 1);
            update_token = new_token;                        
            \$('#btn_send_file').removeAttr("disabled");
            \$('#btn_send_file').attr('src', '/images/send.png');
            showTextInputPanel();
            noReply();
          },
          error: function(xhr, ajaxOptions, thrownError) {
            alert("Unable to upload file. Error " + xhr.status + ": " + thrownError);
            \$('#btn_send_file').removeAttr("disabled");
            \$('#btn_send_file').attr('src', '/images/send.png');
          }                    
        });      
      }
      else {
        alert("Please select a file before click the send button");
      }
    }
    
    function hasGetUserMedia() {
      return !!(navigator.mediaDevices &&
        navigator.mediaDevices.getUserMedia);
    }
    
    function audioInput() {
      if (hasGetUserMedia()) {
        \$('#text_send').hide();
        \$('#file_upload').hide();
        \$('#go_camera').hide();
        \$('#go_file').hide();
        \$('#go_audio').show();
        \$('#sound').click();
      }
      else {
        alert("Your web browser doesn't support audio input.");
      }
    }
    
    function sendSound(group_id, user_id) {
      var send_button_status = \$('#btn_send_sound').attr("disabled");
      if (send_button_status == "disabled") {
        return false;
      }
      
      var file_name = allTrim(\$('#sound').val());   
      if (file_name != "") {
        var sound = \$('#sound').prop('files')[0];
        var form_data = new FormData();
        form_data.append('group_id', group_id);
        form_data.append('sender_id', user_id);
        form_data.append('ul_ftype', 'sound');
        form_data.append('ul_file', sound);
        form_data.append('caption', '');
        form_data.append('op_flag', op_flag);
        form_data.append('op_user_id', op_user_id);
        form_data.append('op_msg', op_msg);
        //*-- Change button image from 'send.png' to 'files_uploading.gif' --*//
        \$('#btn_send_sound').attr('src', '/images/files_uploading.gif');
        //*-- Then disable it to prevent upload a file twice --*//
        \$('#btn_send_sound').attr("disabled", "disabled");
      
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/upload_files.pl',
          dataType: 'text',
          cache: false,
          contentType: false,
          processData: false,
          data: form_data,
          success: function(response) {
            var new_token = response;            
            //*-- Refresh message section (just load the last sent message only) --*//
            loadNewMessages($group_id, $user_id, 1);
            update_token = new_token;                        
            \$('#btn_send_sound').removeAttr("disabled");
            \$('#btn_send_sound').attr('src', '/images/send.png');
            showTextInputPanel();
            noReply();
          },
          error: function(xhr, ajaxOptions, thrownError) {
            alert("Unable to upload sound file. Error " + xhr.status + ": " + thrownError);
            \$('#btn_send_sound').removeAttr("disabled");
            \$('#btn_send_sound').attr('src', '/images/send.png');
          }                    
        });      
      }
      else {
        alert("Please record a sound file before click the send button");
      }      
    }
    
    //-------------------------------------------------------------------------------------------------------//
    
    function getMessageIdListFromOtherSenders() {
      var result = '';
      var buffer = new Array();
      var omid_list = document.querySelectorAll('[id^="omid_"]');
      for (var i = 0; i < omid_list.length; ++i) {
        buffer[i] = omid_list[i].value; 
      }
      result = buffer.join('|');
      
      return result;
    }
                       
    function loadNewMessages(group_id, user_id, last_sent_msg_only) {
      var omid_list = getMessageIdListFromOtherSenders();
      
      \$.ajax({
        type: 'POST',
        url: '/cgi-pl/msg/pull_new_message.pl',
        dataType: 'json',
        data: {group_id: group_id, receiver_id: user_id, last_sent_msg_only: last_sent_msg_only, omid_list: omid_list},
        success: function(ret_data) {
          if (ret_data[0].msg_status == "deleted") {
            hideMessageDeletedByOtherSender(ret_data);
          }
          else {
            addMessageRow(ret_data, last_sent_msg_only);
          }
        },
        error: function(xhr, ajaxOptions, thrownError) {
          alert("Unable to draw new message(s). Error " + xhr.status + ": " + thrownError);
        }             
      });      
    }
    
    function hideMessageDeletedByOtherSender(ret_data) {
      for (var i = 0; i < ret_data.length; i++) {
        var rec = ret_data[i];          
        var this_msg_id = rec.msg_id;

        \$('#row_' + this_msg_id).hide();
        \$('#blankline_' + this_msg_id).hide();
        \$('#omid_' + this_msg_id).remove();
      }      
    }
    
    function addMessageRow(ret_data, last_sent_msg_only) {
      last_sent_msg_only = parseInt(last_sent_msg_only, 10);
    
      for (var i = 0; i < ret_data.length; i++) {
        var rec = ret_data[i];          
        var this_msg_id = rec.msg_id;
        var this_is_my_msg = parseInt(rec.is_my_msg, 10);
        var this_user_color = '#8B0909';
        if (allTrim(rec.user_status) != "A") {this_user_color = '#A4A5A5';}
        var is_member = '';
        if (parseInt(rec.is_member, 10) == 0) {is_member = "(Non member)";}
        var this_sender_id = rec.sender_id;
        var this_sender = "<font color='" + this_user_color + "' size='2px'><b>" + rec.sender + " " + is_member + "</b></font>";
        var this_s_date = rec.s_date;
        var this_s_time_12 = rec.s_time_12;
        var this_from_now = rec.from_now;
        var this_week_day = rec.week_day;
        var this_message = rec.message;
        var this_fileloc = rec.fileloc;
        var this_file_link = rec.file_link;
        var this_op_flag = rec.op_flag;
        var this_op_user = rec.op_user;            
        var this_op_msg = rec.op_msg;        
        var show_time = this_s_time_12;
        //if (this_from_now != "") {show_time = this_from_now;}
        var this_msg_time = "<font color='#31B404' size='2px'>" + show_time + "<font>";
        var is_new_msg = parseInt(rec.is_new_msg, 10);
        var this_msg_30 = rec.msg_30;                   // Used for message replying operation.
        var this_tr = '';
        var re_header = "";
        var fw_header = "";
        
        if (this_file_link.match(/audio controls/gi)) {
          this_file_link = this_file_link + "<br>";
        }
        
        //*-- If it is replied or forward message, process it here. --*//
        if (this_op_flag == 'R') {
          re_header = "<table width='100%' cellspacing=2 cellpadding=6>" +
                      "<tr>" +
                      "  <td style='border-left: 5px solid #0180FF;'>" +
                      "    <font color='#0081FE' size='2px'><b>" + this_op_user + "</b></font><br>" + this_op_msg +
                      "  </td>" +
                      "</tr>" +
                      "</table>";
        }
        else if (this_op_flag == 'F') {
          fw_header = "<font color='#298A09' size='2px'>Forwarded message<br>From <b>" + this_op_user + "</b><br></font>";
        }
                
        if (last_msg_date != this_s_date) {
          var date_tr = "<tr style='background-color:#D9D9D8'><td align=center>" + this_s_date + "</td></tr>";
          \$('#msg_table').append(date_tr).enhanceWithin();
          if (last_sent_msg_only == 1) {
            var blank_tr = "<tr style='height:8px;'><td></td></tr>";
            \$('#msg_table').append(blank_tr).enhanceWithin(); 
          }
          last_msg_date = this_s_date
        }
            
        if (this_is_my_msg) {
          var delete_link = "<a href='javascript:deleteMessage(" + this_msg_id + ");'>Delete</a>";
          var reply_link = "<a href=\\"javascript:replyMessage(" + this_msg_id + ", " + this_sender_id + ", '" + rec.sender + "', '" + this_msg_30 + "');\\">Reply</a>";
          var forward_link = "<a href='javascript:forwardMessage(" + group_id + ", " + this_msg_id + ");'>Forward</a>";
      
          this_tr = "<tr id='row_" + this_msg_id + "'>" +
                    "  <input type='hidden' id='omid_" + this_msg_id + "' name='omid_" + this_msg_id + "' value='" + this_msg_id + "'>" +
                    "  <td width='100%'>" +
                    "    <table width='100%' cellspacing=0 cellpadding=0 style='table-layout:fixed;'>" +
                    "    <tr>" +
                    "      <td width='20%'></td>" +
                    "      <td width='80%' style='background-color:#F4F7CE; word-wrap:break-word;'>" + fw_header + re_header + this_file_link + this_message + "<br>" + this_msg_time + " $spaces " + delete_link + " $space3 " + reply_link + " $space3 " + forward_link + "</td>" +
                    "    </tr>" +
                    "    </table>" +
                    "  </td>" +
                    "</tr>";
        }
        else {
          var reply_link = "<a href=\\"javascript:replyMessage(" + this_msg_id + ", " + this_sender_id + ", '" + rec.sender + "', '" + this_msg_30 + "');\\">Reply</a>";
          var forward_link = "<a href='javascript:forwardMessage(" + group_id + ", " + this_msg_id + ");'>Forward</a>";
        
          this_tr = "<tr id='row_" + this_msg_id + "'>" +
                    "  <input type='hidden' id='omid_" + this_msg_id + "' name='omid_" + this_msg_id + "' value='" + this_msg_id + "'>" +
                    "  <td width='100%'>" +
                    "    <table width='100%' cellspacing=0 cellpadding=0 style='table-layout:fixed;'>" +
                    "    <tr>" + 
                    "      <td width='80%' style='background-color:#E0F8F7; word-wrap:break-word;'>" + this_sender + "<br>" + fw_header + re_header + this_file_link + this_message + "<br>" + this_msg_time + " $spaces " + reply_link + " $space3 " + forward_link + "</td>" +
                    "      <td width='20%'></td>" +
                    "    </tr>" +
                    "    </table>" +
                    "  </td>" +
                    "</tr>";
        }
    
        \$('#msg_table').append(this_tr).enhanceWithin();  
        this_tr = "<tr id='blankline_" + this_msg_id + "' style='height:8px;'><td></td></tr>";
        \$('#msg_table').append(this_tr).enhanceWithin();

        //*-- Seek to last message --*//            
        \$('html, body').animate({scrollTop: \$('#page_end').offset().top}, 500);
      }      
    }
        
    function deleteMessage(msg_id) {
      if (msg_id > 0) {
        parent.stopScheduler();
      
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/delete_message.pl',
          dataType: 'html',
          data: {group_id: group_id, msg_id: msg_id},
          success: function(ret_data) {
            //*-- If message is deleted successfully, hide the row contained the deleted message, and update the value of --*//
            //*-- 'update_token' on do_sms.pl to avoid page refreshing.                                                   --*//
            var result = eval('(' + ret_data + ')');      // Note: Return data in JSON format, so that 'evel' is required.
            var mg_status = result.mg_status;
            var new_token = allTrim(mg_status.update_token);
            parent.update_token = new_token;            
            \$('#row_' + msg_id).hide();
            \$('#blankline_' + msg_id).hide();
            \$('#omid_' + msg_id).remove();
          },
          error: function(xhr, ajaxOptions, thrownError) {
            alert("Unable to delete message. Error " + xhr.status + ": " + thrownError);
          }
        });
        
        runScheduler();
      }
    }
    
    function loadPrevMessages(group_id, user_id) {
      var button_status = \$('#btn_load_more').attr("disabled");
      if (button_status == "disabled") {
        return false;
      }

      //*-- Change button image from 'readmore.png' to 'files_uploading.gif' --*//
      \$('#btn_load_more').attr('src', '/images/files_uploading.gif');
      //*-- Then disable it to prevent load more than one message block --*//
      \$('#btn_load_more').attr("disabled", "disabled");
        
      //*-- Note: 'first_msg_id' means the ID of the first message which has already loaded --*//
      \$.ajax({
        type: 'POST',
        url: '/cgi-pl/msg/pull_prev_message.pl',
        dataType: 'json',
        data: {group_id: group_id, receiver_id: user_id, first_msg_id: first_msg_id, rows_limit: $rows_limit},
        success: function(ret_data) {
          first_msg_id = addPrevMessageRow(ret_data);
          if (is_iOS) {
            Cookies.set("m_id", first_msg_id, {expires: 1});      // Defined on js.cookies.min.js
          }
          else {
            setLocalStoredItem("m_id", first_msg_id);             // Defined on common_lib.js
          }
          \$('#btn_load_more').removeAttr("disabled");
          \$('#btn_load_more').attr('src', '/images/readmore.png');          
        },
        error: function(xhr, ajaxOptions, thrownError) {
          alert("Unable to draw previous message(s). Error " + xhr.status + ": " + thrownError);
          \$('#btn_load_more').removeAttr("disabled");
          \$('#btn_load_more').attr('src', '/images/readmore.png');                    
        }             
      });            
    }
        
    function addPrevMessageRow(ret_data) {
      var the_msg_id = 0;
      
      for (var i = 0; i < ret_data.length; i++) {
        var rec = ret_data[i];          
        var this_msg_id = rec.msg_id;
        var this_is_my_msg = parseInt(rec.is_my_msg, 10);
        var this_user_color = '#8B0909';
        if (allTrim(rec.user_status) != "A") {this_user_color = '#A4A5A5';}
        var is_member = '';
        if (parseInt(rec.is_member, 10) == 0) {is_member = "(Non member)";}
        var this_sender_id = rec.sender_id;
        var this_sender = "<font color='" + this_user_color + "' size='2px'><b>" + rec.sender + " " + is_member + "</b></font>";
        var this_s_date = rec.s_date;
        var this_s_time_12 = rec.s_time_12;
        var this_from_now = rec.from_now;
        var this_week_day = rec.week_day;
        var this_message = rec.message;
        var this_fileloc = rec.fileloc;
        var this_file_link = rec.file_link;
        var this_op_flag = rec.op_flag;
        var this_op_user = rec.op_user;            
        var this_op_msg = rec.op_msg;        
        var show_time = this_s_time_12;
        var this_msg_time = "<font color='#31B404' size='2px'>" + show_time + "<font>";
        var is_new_msg = parseInt(rec.is_new_msg, 10);
        var this_msg_30 = rec.msg_30;                   // Used for message replying operation.
        var this_tr = '';
        var re_header = "";
        var fw_header = "";

        //*-- With reason still unknown, extra garbage record(s) may be embedded in the return data, so it needs to --*//
        //*-- take this checking for returned records.                                                              --*//
        if (this_msg_id != undefined) {        
          if (this_file_link.match(/audio controls/gi)) {
            this_file_link = this_file_link + "<br>";
          }
        
          //*-- If it is replied or forward message, process it here. --*//
          if (this_op_flag == 'R') {
            re_header = "<table width='100%' cellspacing=2 cellpadding=6>" +
                        "<tr>" +
                        "  <td style='border-left: 5px solid #0180FF;'>" +
                        "    <font color='#0081FE' size='2px'><b>" + this_op_user + "</b></font><br>" + this_op_msg +
                        "  </td>" +
                        "</tr>" +
                        "</table>";
          }
          else if (this_op_flag == 'F') {
            fw_header = "<font color='#298A09' size='2px'>Forwarded message<br>From <b>" + this_op_user + "</b><br></font>";
          }
                
          if (first_msg_date != this_s_date) {
            var blank_tr = "<tr style='height:8px;'><td></td></tr>";
            \$('#msg_table > tbody > tr').eq(0).before(blank_tr).enhanceWithin();                                  
            var date_tr = "<tr style='background-color:#D9D9D8'><td align=center>" + this_s_date + "</td></tr>";
            \$('#msg_table > tbody > tr').eq(0).before(date_tr).enhanceWithin();
            first_msg_date = this_s_date
          }
                                
          if (this_is_my_msg) {
            var delete_link = "<a href='javascript:deleteMessage(" + this_msg_id + ");'>Delete</a>";
            var reply_link = "<a href=\\"javascript:replyMessage(" + this_msg_id + ", " + this_sender_id + ", '" + rec.sender + "', '" + this_msg_30 + "');\\">Reply</a>";
            var forward_link = "<a href='javascript:forwardMessage(" + group_id + ", " + this_msg_id + ");'>Forward</a>";
      
            this_tr = "<tr id='row_" + this_msg_id + "'>" +
                      "  <input type='hidden' id='omid_" + this_msg_id + "' name='omid_" + this_msg_id + "' value='" + this_msg_id + "'>" +
                      "  <td width='100%'>" +
                      "    <table width='100%' cellspacing=0 cellpadding=0 style='table-layout:fixed;'>" +
                      "    <tr>" +
                      "      <td width='20%'></td>" +
                      "      <td width='80%' style='background-color:#F4F7CE; word-wrap:break-word;'>" + fw_header + re_header + this_file_link + this_message + "<br>" + this_msg_time + " $spaces " + delete_link + " $space3 " + reply_link + " $space3 " + forward_link + "</td>" +
                      "    </tr>" +
                      "    </table>" +
                      "  </td>" +
                      "</tr>";
          }
          else {
            var reply_link = "<a href=\\"javascript:replyMessage(" + this_msg_id + ", " + this_sender_id + ", '" + rec.sender + "', '" + this_msg_30 + "');\\">Reply</a>";
            var forward_link = "<a href='javascript:forwardMessage(" + group_id + ", " + this_msg_id + ");'>Forward</a>";
        
            this_tr = "<tr id='row_" + this_msg_id + "'>" +
                      "  <input type='hidden' id='omid_" + this_msg_id + "' name='omid_" + this_msg_id + "' value='" + this_msg_id + "'>" +
                      "  <td width='100%'>" +
                      "    <table width='100%' cellspacing=0 cellpadding=0 style='table-layout:fixed;'>" +
                      "    <tr>" + 
                      "      <td width='80%' style='background-color:#E0F8F7; word-wrap:break-word;'>" + this_sender + "<br>" + fw_header + re_header + this_file_link + this_message + "<br>" + this_msg_time + " $spaces " + reply_link + " $space3 " + forward_link + "</td>" +
                      "      <td width='20%'></td>" +
                      "    </tr>" +
                      "    </table>" +
                      "  </td>" +
                      "</tr>";
          }
    
          \$('#msg_table > tbody > tr').eq(0).after(this_tr).enhanceWithin();
          this_tr = "<tr id='blankline_" + this_msg_id + "' style='height:8px;'><td></td></tr>";
          \$('#msg_table > tbody > tr').eq(0).after(this_tr).enhanceWithin();            
        
          the_msg_id = this_msg_id;
        }
      }
      
      //*-- Try to retrieve the first message id of this group of this user (Note: It may not exist) --*//
      var top_msg_id = (is_iOS)? Cookies.get("top_id") : getLocalStoredItem("top_id");   // Defined on js.cookie.min.js : common_lib.js
      top_msg_id = (top_msg_id == undefined)? 0 : top_msg_id;
      
      if (ret_data.length < $rows_limit || the_msg_id == top_msg_id) {
        \$('#read_more').hide();
        if (the_msg_id != top_msg_id) {
          if (is_iOS) {
            Cookies.set("top_id", the_msg_id, {expires: 1});
          }
          else {
            setLocalStoredItem("top_id", the_msg_id);
          }
        }
      }

      //*-- Return the most updated value of 'first_msg_id' --*//      
      return the_msg_id;
    }
  </script>
__JS
}


sub printMessagesForm {
  my ($group_id, $group_role) = @_;
  my ($html, $panel, $admin_options, $group_marker, $prv_s_date, $new_msg_start, $spaces, $space3, $blank_line, $read_more);
  
  $group_marker = ($group_type == 1)? "<img src='/images/lock.png' height='15px'>" : "";
  $spaces = '&nbsp;' x 8;
  $space3 = '&nbsp;' x 3;
  $blank_line = "<tr style='height:8px;'><td></td></tr>";
  $new_msg_start = 'W';            # 'W' = Wait for new message (if any), 'S' = New message has been met and new message seperator line been shown.
  $read_more = (scalar(@message) >= $rows_limit && $message[0]->{'msg_id'} != $top_id)? "<img id='btn_load_more' src='/images/readmore.png' height='50px' onClick='loadPrevMessages($group_id, $user_id);'><br>" : '';
    
  if ($group_role == 1 || $user_role == 2) {               # Message group admin or system admin.
    if (isPrivateGroup($dbh, $group_id)) {                 # Defined on sm_msglib.pl
      #-- For private messaging group (1 to 1), operations of adding member, member deletion, promoting user to group admin., --#
      #-- and demote admin. to member are not relevance.                                                                      --#
      $admin_options = <<__HTML;
      <li data-role="list-divider" style="color:darkgreen;">Group Administration</li>
      <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=8&g_id=$group_id" data-ajax="false">Auto Delete Setup</a></li>
__HTML
    }
    else {
      $admin_options = <<__HTML;
      <li data-role="list-divider" style="color:darkgreen;">Group Administration</li>
			<li><a href="/cgi-pl/msg/edit_group_profile.pl?op=3&g_id=$group_id" data-ajax="false">Add Member</a></li>
      <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=4&g_id=$group_id" data-ajax="false">Delete Member</a></li>            
      <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=6&g_id=$group_id" data-ajax="false">Promote Member</a></li>
      <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=7&g_id=$group_id" data-ajax="false">Demote Admin</a></li>
      <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=9&g_id=$group_id" data-ajax="false">Inform Member</a></li>
__HTML
    }
    
    #-- Group administrator --#
    $panel = <<__HTML;
      <div data-role="panel" data-position-fixed="true" data-position="left" data-display="overlay" id="setup">
        <div data-role="main" class="ui-content">
          <ul data-role="listview">
            <li><a href="javascript:goHome();" data-ajax="false">Go Home</a></li>
            <li data-role="list-divider" style="color:darkgreen;">Group Profile</li>
            <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=1&g_id=$group_id" data-ajax="false">Change Group Name</a></li>
					  <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=2&g_id=$group_id" data-ajax="false">List Member</a></li>            
            <li><a href="javascript:quitMessageGroup($group_id, $user_id);" data-ajax="false">Exit Group</a></li>
            $admin_options
            <li data-role="list-divider" style="color:darkgreen;">Emergency</li>
            <li><a href="javascript:deleteThisGroup($group_id);" data-ajax="false">Delete Group</a></li>
				  </ul>	
			  </div>
      </div>	    
__HTML
  }
  else {
    #-- Ordinary group member --# 
    $panel = <<__HTML;
      <div data-role="panel" data-position-fixed="true" data-position="left" data-display="overlay" id="setup">
        <div data-role="main" class="ui-content">
          <ul data-role="listview">
            <li><a href="javascript:goHome();" data-ajax="false">Go Home</a></li> 
            <li data-role="list-divider" style="color:darkgreen;">Group Profile</li>
            <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=1&g_id=$group_id" data-ajax="false">Change Group Name</a></li>
					  <li><a href="/cgi-pl/msg/edit_group_profile.pl?op=2&g_id=$group_id" data-ajax="false">List Member</a></li>            
            <li><a href="javascript:quitMessageGroup($group_id, $user_id);" data-ajax="false">Exit Group</a></li>
				  </ul>	
			  </div>
      </div>	    
__HTML
  }
  
  $html = <<__HTML;
  <div data-role="page">
    $panel
    
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
	    <a href="#setup" data-icon="bars" class="ui-btn-left">Setup</a>					
		  <h1>$group_marker$group_name</h1>
		  <a href="javascript:logoutSMS();" data-icon="power" class="ui-btn-right" data-ajax="false">Quit</a>
	  </div>	
    
    <div data-role="content" style="overflow-y:auto;" data-position="fixed" data-tap-toggle="false">
      <table id="msg_table" width=100% cellspacing=0 cellpadding=0 style="table-layout:fixed;">
      <thead><tr id="read_more"><td align=center valign=center>$read_more</td></tr></thead>
      <tbody>
__HTML
      
  $prv_s_date = '';
  foreach my $rec (@message) {
    my $this_msg_id = $rec->{'msg_id'} + 0;
    my $this_is_my_msg = $rec->{'is_my_msg'} + 0;
    my $this_user_color = ($rec->{'user_status'} eq 'A')? '#8B0909' : '#A4A5A5';
    my $is_member = ($rec->{'is_member'} == 0)? "(Non member)" : '';
    my $this_sender_id = $rec->{'sender_id'} + 0;
    my $this_sender = "<font color='$this_user_color' size='2px'><b>$rec->{'sender'} $is_member</b></font>";
    my $this_s_date = $rec->{'s_date'};
    my $this_s_time_12 = $rec->{'s_time_12'};
    my $this_from_now = $rec->{'from_now'};
    my $this_week_day = $rec->{'week_day'};
    my $this_message = $rec->{'message'};
    my $this_fileloc = $rec->{'fileloc'};
    my $this_file_link = $rec->{'file_link'};
    my $this_op_flag = $rec->{'op_flag'};
    my $this_op_user = $rec->{'op_user'};            
    my $this_op_msg = $rec->{'op_msg'};
    my $this_msg_time = "<font color='#31B404' size='2px'>$this_s_time_12<font>";
    my $is_new_msg = $rec->{'is_new_msg'} + 0;
    my $this_msg_30 = $rec->{'msg_30'};             # Used for message replying operation.
    my $fw_header = '';
    my $re_header = '';
    my $this_tr = '';
    
    if ($this_file_link =~ /audio controls/gi) {
      $this_file_link .= "<br>";
    }
        
    $this_message =~ s/\n/<br>/g;
    $this_op_msg =~ s/\n/<br>/g;
    $this_msg_30 =~ s/'/¡/g;                        # All single quote characters are replaced by '¡'.
    
    #-- If it is replied or forward message, process it here. --#
    if ($this_op_flag eq 'R') {
      $re_header = <<__HTML;
      <table width="100%" cellspacing=2 cellpadding=6>
      <tr>
        <td style="border-left: 5px solid #0180FF;">
          <font color='#0081FE' size='2px'><b>$this_op_user</b></font><br>$this_op_msg
        </td>
      </tr>
      </table>
__HTML
    }
    elsif ($this_op_flag eq 'F') {
      $fw_header = "<font color='#298A09' size='2px'>Forwarded message<br>From <b>$this_op_user</b><br></font>";
    }
    
    #-- Show date --#
    if ($prv_s_date ne $this_s_date) {
      $html .= <<__HTML;
      <tr style="background-color:#D9D9D8"><td align=center>$this_s_date</td></tr>
      $blank_line
__HTML
      $prv_s_date = $this_s_date;
    }

    #-- Show new message separation marker --#
    if ($is_new_msg && $new_msg_start eq 'W') {
      $html .= <<__HTML;
      <tr id="new_msg" style="background-color:#F5A8BD"><td align=center>New Message(s) Below</td></tr>
      $blank_line
__HTML
      $new_msg_start = 'S';
    }
    
    if ($this_is_my_msg) {
      my $delete_link = "<a href='javascript:deleteMessage($this_msg_id);'>Delete</a>";
      my $reply_link = "<a href=\"javascript:replyMessage($this_msg_id, $this_sender_id, '$rec->{'sender'}', '$this_msg_30');\">Reply</a>";
      my $forward_link = "<a href='javascript:forwardMessage($group_id, $this_msg_id);'>Forward</a>";
      
      $this_tr = <<__HTML;
      <tr id="row_$this_msg_id">
        <input type="hidden" id="omid_$this_msg_id" name="omid_$this_msg_id" value="$this_msg_id">
        <td width="100%">
          <table width="100%" cellspacing=0 cellpadding=0 style="table-layout:fixed;">
          <tr>
            <td width="20%"></td>
            <td width="80%" style="background-color:#F4F7CE; word-wrap:break-word;">$fw_header$re_header$this_file_link$this_message<br>$this_msg_time $spaces $delete_link $space3 $reply_link $space3 $forward_link</td>
          </tr>
          </table>
        </td>
      </tr>
__HTML
    }
    else {
      my $reply_link = "<a href=\"javascript:replyMessage($this_msg_id, $this_sender_id, '$rec->{'sender'}', '$this_msg_30');\">Reply</a>";
      my $forward_link = "<a href='javascript:forwardMessage($group_id, $this_msg_id);'>Forward</a>";
      
      $this_tr = <<__HTML;
      <tr id="row_$this_msg_id">
        <input type="hidden" id="omid_$this_msg_id" name="omid_$this_msg_id" value="$this_msg_id">
        <td width="100%">
          <table width="100%" cellspacing=0 cellpadding=0 style="table-layout:fixed;">
          <tr>
            <td width="80%" style="background-color:#E0F8F7; word-wrap:break-word;">$this_sender<br>$fw_header$re_header$this_file_link$this_message<br>$this_msg_time $spaces $reply_link $space3 $forward_link</td>
            <td width="20%"></td>
          </tr>
          </table>
        </td>
      </tr>
__HTML
    }
    
    $this_tr .= "<tr id='blankline_$this_msg_id' style='height:8px;'><td></td></tr>";    
    $html .= $this_tr;
  }
            
  $html .= <<__HTML;    
      </tbody>
      </table>
    </div>
    
    <div id="page_end" style="overflow-y:auto;"></div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellpadding=1 cellspacing=1>
      <thead>
        <tr><td></td></tr>
      </thead>
      <tbody>
        <tr id="reply_row">
         <td colspan=4>
           <table width=100% cellpadding=0 cellspacing=0>
           <thead>
             <tr><td></td></tr>
           </thead>
           <tbody>
             <tr>
               <td align=center align=center><img src="/images/reply.png" width="28px"></td>
               <td width="75%" id="reply_msg_area"></td>
               <td align=center align=center><img src="/images/cross.png" width="30px" onClick="javascript:noReply();"></td>
             </tr>
           </tbody>
           </table>
          </td>
        </tr>
        
        <tr id="text_send">
          <td width="78%" id="msg_area"><textarea id="s_message" name="s_message" autofocus data-role="none" class="s_message"></textarea></td>
          <td id="btn_msg_send" align=center valign=bottom><a href="javascript:sendMessage($group_id, $user_id);"><img src="/images/send.png" width="40px"></a></td>
          <td id="btn_attach_file" align=center><a href="javascript:attachFile();"><img src="/images/attachment.png" width="30px"></a></td>
          <td id="btn_audio_input" align=center><a href="javascript:audioInput();"><img src="/images/mic.png" width="20px"></a></td>          
        </tr>
        
        <tr id="file_upload" style="display:none">
          <td colspan=4>
            <table width=100% cellspacing=0 cellpadding=0>
            <thead><tr><td></td></tr></thead>
            <tbody>
            <tr>
              <td align=center valign=top><img src="/images/camera.png" width="50px" onClick="openCamera();"><br>Camera</td>
              <td align=center valign=top><img src="/images/file.png" width="50px" onClick="selectFileToUpload();"><br>File</td>
              <td align=center valign=top><img src="/images/hide.png" width="50px" onClick="showTextInputPanel();"></td>
            </tr>
            </tbody>
            </table>
          </td>
        </tr>
        
        <tr id="go_camera" style="display:none">
          <td colspan=4>
            <table width=100% cellspacing=0 cellpadding=0>
            <thead><tr><td></td></tr></thead>
            <tbody>
            <tr>
              <td align=center valign=center nowap>
                <img src="/images/hide.png" width="50px" onClick="showTextInputPanel();">
              </td>                        
              <td width="65%" valign=center>
                <input type="file" id="photo" name="photo" accept="image/*" capture="camera">
                <input type=text id="caption" name="caption"> 
              </td>
              <td align=center valign=center nowap>
                <img id="btn_send_photo" src="/images/send.png" width="50px" onClick="sendPhoto($group_id, $user_id);">
              </td>
            </tr>
            </tbody>
            </table>          
          </td>
        </tr>
        
        <tr id="go_file" style="display:none">
          <td colspan=4>
            <table width=100% cellspacing=0 cellpadding=0>
            <thead><tr><td></td></tr></thead>
            <tbody>
            <tr>
              <td align=center valign=center nowap>
                <img src="/images/hide.png" width="50px" onClick="showTextInputPanel();">
              </td>            
              <td width="65%" valign=center>
                <input type="file" id="ul_file" name="ul_file">
              </td>
              <td align=center valign=center nowap>
                <img id="btn_send_file" src="/images/send.png" width="50px" onClick="sendFile($group_id, $user_id);">
              </td>
            </tr>
            </tbody>
            </table>
          </td>  
        </tr>
        
        <tr id="go_audio" style="display:none">
          <td colspan=4>
            <table width=100% cellspacing=0 cellpadding=0>
            <thead><tr><td></td></tr></thead>
            <tbody>
            <tr>
              <td align=center valign=center nowap>
                <img src="/images/hide.png" width="50px" onClick="showTextInputPanel();">
              </td>                        
              <td width="65%" valign=center>
                <input type="file" id="sound" name="sound" accept="audio/*" capture="microphone">
              </td>
              <td align=center valign=center nowap>
                <img id="btn_send_sound" src="/images/send.png" width="50px" onClick="sendSound($group_id, $user_id);">
              </td>
            </tr>
            </tbody>
            </table>          
          </td>          
        </tr>
      </tbody>  
      </table>
    </div>    
  </div>
__HTML
  
  print $html;
}
