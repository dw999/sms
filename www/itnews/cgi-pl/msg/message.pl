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
# Program: /www/itnews/cgi-pl/msg/message.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-14      AY              Show the main page of the messaging system.
# V1.0.01       2018-08-06      AY              Add a scheduler to refresh this page per 30 seconds.
# V1.0.02       2018-08-08      AY              Show private group indicator (a lock icon).
# V1.0.03       2018-09-23      AY              - Add a new option for Telegram bot profile maintenance
#                                                 for system administrators.
#                                               - Add a new option for Telegram ID input on user
#                                                 profile maintenance.
# V1.0.04       2018-09-28      AY              Add system settings link
# V1.0.05       2019-01-07      AY              Show user creation option on menu as connection mode
#                                               is 1 or 3.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                                           # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my $user_role = getUserRole($dbh, $user_id);               # Defined on sm_user.pl
my @msgrp = getMessageGroup($dbh, $user_id);               # Defined on sm_msglib.pl

printStyleSection();
printJavascriptSection();
printMessageTheme();

dbclose($dbh);
#-- End Main Section --#


sub printStyleSection {
  print <<__STYLE;
  <style>
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
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  
  <script>
    var message_scheduler_id;
  
    \$(document).on("pageshow", function(event) {
      runMessageScheduler();
    });
    
//    function runMessageScheduler() {
//      message_scheduler_id = setInterval(refreshPage, 30000);
//      
//      function refreshPage() {
//        window.location.href = "/cgi-pl/msg/message.pl";
//      }
//    }  

    function runMessageScheduler() {
      message_scheduler_id = setInterval(refreshPage, 10000);
      
      function refreshPage() {
        \$.ajax({
          type: 'POST',
          url: '/cgi-pl/msg/check_new_message_count.pl',
          dataType: 'json',
          data: {user_id: $user_id},
          success: function(ret_data) {
            refreshMessageCount(ret_data);
          },
          error: function(xhr, ajaxOptions, thrownError) {
            //alert("Unable to refresh message home page. Error " + xhr.status + ": " + thrownError);
          }
        });              
      }
    }
    
    function refreshMessageCount(ret_data) {
      var private_group_marker = "<img src='/images/lock.png' height='15px'>";
    
      for (var i = 0; i < ret_data.length; i++) {
        var rec = ret_data[i];          
        var this_group_id = parseInt(rec.group_id, 10);
        var this_group_name = rec.group_name;
        var this_group_type = parseInt(rec.group_type, 10);
        var this_unread_cnt = parseInt(rec.unread_cnt, 10);
        var this_marker = (this_group_type == 1)? private_group_marker : ''; 

        //*-- Update unread message counter shown --*//
        \$('#grp_' + this_group_id).html(this_marker + this_group_name + "<br><font size='2pt'>New message: " + this_unread_cnt + "</font>");          
      }      
    }
    
    function doomEntireSystem() {
      //*-- Just don't do it at home :-) --*//
      if (confirm("Do you really want to destory entire system?")) {
        if (confirm("Last chance! Really want to go?")) {
          var url = "/cgi-pl/admin/destroy_entire_system.pl";
          window.location.href = url;
        }
      }
    }
  </script>
__JS
}


sub printMessageTheme {
	my ($html, $panel, $private_group_marker, $telegram_id_input, $connect_mode, $create_user_account);
	
  $private_group_marker = "<img src='/images/lock.png' height='15px'>";
  
  if (telegramBotDefined($dbh)) {          # Defined on sm_webenv.pl
    $telegram_id_input = <<__HTML;
    <li><a href="/cgi-pl/user/edit_profile.pl?op=5" data-ajax="false">Telegram ID</a></li>
__HTML
  }
  else {
    $telegram_id_input = '';
  }
  
  $connect_mode = getSysSettingValue($dbh, 'connection_mode') + 0;
  if ($connect_mode == 1 || $connect_mode == 3) {    # Defined on sm_webenv.pl
    #-- If Gmail is unable to be used as communication media, or don't want SMS to be registered by outsider, then --#
    #-- user creation process must be handled directly by trusted users and system administrators.                 --# 
    $create_user_account = <<__HTML;
    <li><a href="/cgi-pl/user/create_msg_user.pl" data-ajax="false"_>Create User</a></li>
__HTML
  }
  else {
    $create_user_account = '';
  }
  
	if ($user_role < 2) {
    #-- Note: As panel is opened, it will scroll page content to top. To stop this default behavior, we set data-position-fixed="true" and --#
    #--       define CSS ".ui-panel.ui-panel-open" and ".ui-panel-inner" to make the inner part of the panel contents scroll independent   --#
    #--       from the main content page and avoid dual scrolling. Details please refer to URL below:                                      --#
    #--       https://stackoverflow.com/questions/22672236/jquery-mobile-panel-open-scrolls-page-to-the-top-how-to-change-this#22675170    --#
    $panel = <<__HTML;
    <div data-role="panel" data-position-fixed="true" data-position="left" data-display="overlay" id="setup">
      <div data-role="main" class="ui-content">
        <ul data-role="listview">
          <li data-role="list-divider" style="color:darkgreen;">Maintain Your Profile</li>
          <li><a href="/cgi-pl/user/edit_profile.pl?op=1" data-ajax="false">Alias</a></li>
					<li><a href="/cgi-pl/user/edit_profile.pl?op=2" data-ajax="false">Email</a></li>
          $telegram_id_input
          <li><a href="/cgi-pl/user/edit_profile.pl?op=3" data-ajax="false">Happy Password</a></li>
					<li><a href="/cgi-pl/user/edit_profile.pl?op=4" data-ajax="false">Unhappy Password</a></li>
          <li data-role="list-divider" style="color:darkgreen;">Message Group</li>
          <li><a href="/cgi-pl/msg/add_group.pl" data-ajax="false">Add Group</a></li>
          <li><a href="/cgi-pl/msg/add_private_group.pl" data-ajax="false">Add Private Group</a></li>
				</ul>	
			</div>
    </div>			
__HTML
  }
	else {
    $panel = <<__HTML;
    <div data-role="panel" data-position-fixed="true" data-position="left" data-display="overlay" id="setup">
      <div data-role="main" class="ui-content">
        <ul data-role="listview">
          <li data-role="list-divider" style="color:darkgreen;">Maintain Your Profile</li>
          <li><a href="/cgi-pl/user/edit_profile.pl?op=1" data-ajax="false">Alias</a></li>
					<li><a href="/cgi-pl/user/edit_profile.pl?op=2" data-ajax="false">Email</a></li>
          $telegram_id_input
          <li><a href="/cgi-pl/user/edit_profile.pl?op=3" data-ajax="false">Happy Password</a></li>
					<li><a href="/cgi-pl/user/edit_profile.pl?op=4" data-ajax="false">Unhappy Password</a></li>
          <li data-role="list-divider" style="color:darkgreen;">Message Group</li>
          <li><a href="/cgi-pl/msg/add_group.pl" data-ajax="false">Add Group</a></li>
          <li><a href="/cgi-pl/msg/add_private_group.pl" data-ajax="false">Add Private Group</a></li>
					<li><a href="/cgi-pl/msg/delete_group_by_admin.pl" data-ajax="false">Delete Group</a></li>
					<li data-role="list-divider" style="color:darkgreen;">System Administration</li>
          $create_user_account
          <li><a href="/cgi-pl/admin/promote_user.pl" data-ajax="false">Promote User</a></li>
          <li><a href="/cgi-pl/admin/demote_user.pl" data-ajax="false">Demote User</a></li>
          <li><a href="/cgi-pl/admin/lock_user.pl" data-ajax="false">Lock/Unlock User</a></li>
          <li><a href="/cgi-pl/admin/system_setup.pl" data-ajax="false">System Settings</a></li>
					<li><a href="javascript:doomEntireSystem();" data-ajax="false">Destroy System</a></li>
				</ul>	
			</div>
    </div>			
__HTML
	}
  	
	#-- Important: 'data-ajax="false"' must be set for links with dynamic content. Otherwise, unexpected result such as invalid javascript --#
	#--            content and expired passed parameters value will be obtained.                                                           --#
  $html = <<__HTML;
	<div data-role="page" id="mainpage">
	  $panel
	
	  <div data-role="header" style="overflow:hidden;" data-position="fixed">
		  <a href="#setup" data-icon="bars" class="ui-btn-left">Setup</a>					
			<h1>SMS 1.0</h1>
			<a href="/cgi-pl/auth/logout.pl" data-icon="power" class="ui-btn-right" data-ajax="false">Quit</a>					
		</div>	

		<div data-role="main" class="ui-body-d ui-content">
__HTML

  if (scalar(@msgrp) > 0) {
		$html .= <<__HTML;
		<div class="ui-grid-solo">
__HTML
		
		foreach my $rec (@msgrp) {
      my $this_group_id = $rec->{'group_id'} + 0;
      my $this_group_name = $rec->{'group_name'};
      my $this_group_type = $rec->{'group_type'} + 0;
      my $this_group_role = $rec->{'group_role'};
      my $this_unread_cnt = $rec->{'unread_cnt'} + 0;
			my $this_link = "/cgi-pl/msg/do_sms.pl?g_id=$this_group_id";
	    my $this_marker = ($this_group_type == 1)? $private_group_marker : ''; 
            				
      $html .= <<__HTML;
			<a href="$this_link" id="grp_$this_group_id" class="ui-btn ui-corner-all ui-shadow" data-ajax="false">$this_marker$this_group_name<br><font size="2pt">New message: $this_unread_cnt</font></a>
__HTML
		}
		
		$html .= <<__HTML;
		</div>
__HTML
  }
  else {
		$html .= <<__HTML;
		<p><a href="/cgi-pl/msg/add_group.pl" data-role="button" data-ajax="false">Add Group</a></p>
    <p><a href="/cgi-pl/msg/add_private_group.pl" data-role="button" data-ajax="false">Add Private Group</a></p>
__HTML
	}
		  			
	$html .= <<__HTML;		
		</div>
	</div>
__HTML

  print "$html";
}
