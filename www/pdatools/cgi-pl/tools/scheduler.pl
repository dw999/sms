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
# Program: /www/pdatools/cgi-pl/tools/scheduler.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-19      DW              A scheduler.
#
# Remark: Event reminder is handled by another back-end program 'schedule_reminder.pl'.
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

my $op = paramAntiXSS('op');                                          # 'A' = Add new event, 'E' = Modify event, 'D' = Delete event, 'R' = Read event, 'L' = List events, 'S' = Search event, others = Show calender. 
my $oper_mode = paramAntiXSS('oper_mode');                            # 'S' = Save
my $list_filter = paramAntiXSS('list_filter');                        # Key words filter on event's title for event searching.
my $what_year = paramAntiXSS('what_year') + 0;
my $what_month = paramAntiXSS('what_month') + 0;
my $event_id = paramAntiXSS('event_id') + 0;
my $event_title = paramAntiXSS('event_title');
my $event_detail = paramAntiXSS('event_detail');
my $event_start = paramAntiXSS('event_start');
my $event_end = paramAntiXSS('event_end');
my $has_reminder = paramAntiXSS('has_reminder') + 0;                  # 0 = No reminder, 1 = has reminder.
my $search_phase = paramAntiXSS('search_phase');                      # Text phase is used for event searching.
my $call_by = paramAntiXSS('call_by');                                # Call by who?
my @reminder = ($has_reminder)? getEventReminder() : ();              # For event adding and editing.

my $dbh = dbconnect($COOKIE_PDA);

my %user_info = printHead($COOKIE_PDA);                               # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @event_list;
my %event_dtl;
my @reminder_list;                                                    # For specified event only.
my $ok = 1;
my $msg = '';

if ($op eq 'R' || $op eq 'E') {
  if ($oper_mode ne 'S') {
    %event_dtl = getEventDetail($dbh, $event_id);
    @reminder_list = getReminderListForEvent($dbh, $event_id);    
  }
}

printJavascriptSection();

if ($op eq 'A') {
  if ($oper_mode eq 'S') {
    my ($ok, $msg) = addNewEvent($dbh, $user_id, $event_title, $event_detail, $event_start, $event_end, \@reminder);
    if ($ok) {
      redirectTo("/cgi-pl/tools/scheduler.pl?what_year=$what_year&what_month=$what_month");
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    printAddEventForm($dbh, $event_start, $event_end);
  }  
}
elsif ($op eq 'E') {
  if ($oper_mode eq 'S') {
    my ($ok, $msg) = updateEvent($dbh, $event_id, $event_title, $event_detail, $event_start, $event_end, \@reminder);
    if ($ok) {
      redirectTo("/cgi-pl/tools/scheduler.pl?what_year=$what_year&what_month=$what_month&event_id=$event_id&op=R");
    }
    else {
      alert($msg);
      back();
    }    
  }
  else {
    printEditEventForm(\%event_dtl, \@reminder_list);
  }
}
elsif ($op eq 'D') {
  my ($ok, $msg) = deleteEvent($dbh, $event_id);
  if ($ok) {
    redirectTo("/cgi-pl/tools/scheduler.pl?what_year=$what_year&what_month=$what_month");
  }
  else {
    alert($msg);
    back();
  }
}
elsif ($op eq 'R') {
  printReadEventForm(\%event_dtl, \@reminder_list);
}
elsif ($op eq 'L') {
  @event_list = getEventList($dbh, $user_id);
  printEventList(\@event_list);
}
elsif ($op eq 'S') {
  if (allTrim($search_phase) ne '') {
    my @search_records = searchEvents($dbh, $user_id, $search_phase);
    printSearchResult(\@search_records);
  }
  else {
    printSearchForm();
  }
}
else {
  if ($what_year <= 0 || $what_month <= 0) {
    ($what_year, $what_month) = getCurrentYearAndMonth($dbh);
  }
  
  printStyleSection();
  printCalendar($dbh, $what_year, $what_month);
}

dbclose($dbh);
#-- End Main Section --#


sub getEventReminder {
  my (%params, @result);
  
  %params = parameter(param);               # Defined on sm_webenv.pl
  foreach my $this_key (keys %params) {
    if ($this_key =~ /rd_value_/) {
      my $idx = $this_key;
      $idx =~ s/rd_value_//g;
      $idx += 0;
      
      my $this_rd_value = $params{$this_key};
      my $this_rd_unit = allTrim($params{'rd_unit_' . $idx});
      my $this_rd_id = ($op eq 'E')? $params{'rd_id_' . $idx} + 0 : 0;
      
      if ($this_rd_value > 0 && $this_rd_unit ne '') {
        push @result, {'rd_value' => $this_rd_value, 'rd_unit' => $this_rd_unit, 'rd_id' => $this_rd_id};
      }      
    }    
  }
  
  return @result;  
}


sub printJavascriptSection {
  my ($is_reminder_exist, $go_first_active_event);
  
  $is_reminder_exist = ($op eq 'E' && scalar(@reminder_list) > 0)? 1 : 0;

  if ($op eq 'L') {
    $go_first_active_event = <<__JS
    \$(document).on("pageinit", function() {
      \$(function() {
        \$('html,body').animate({scrollTop: \$('#first_active_event').offset().top}, 400);
      })
    });    
__JS
  }
    
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
  <link rel="stylesheet" href="/js/jquery-ui-min.css">
  <link rel="stylesheet" type="text/css" href="/js/DateTimePicker.min.css"/>  
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
	<script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/DateTimePicker.min.js"></script>
  <!--[if lt IE 9]>
  <link rel="stylesheet" type="text/css" href="/js/DateTimePicker-ltie9.min.css"/>
  <script type="text/javascript" src="/js/DateTimePicker-ltie9.min.js"></script>
  <![endif]-->
  <script src="/js/common_lib.js"></script>
  
  <script>
    var current_op = "$op";
    var is_reminder_exist = $is_reminder_exist;

    $go_first_active_event
  
    \$(document).on("pagebeforeshow", function() {
      \$('#dt_box').DateTimePicker({
        mode: "datetime",
        dateTimeFormat: "yyyy-MM-dd HH:mm"
      });
    });
    
    if (current_op == "A" || current_op == "E") {
      if (current_op == "A" || (current_op == "E" && is_reminder_exist == 1)) {    
        \$(document).on("pagebeforeshow", function() {
          addReminder('rd_row_1');
        });
      }
      else {
        \$(document).on("pagebeforeshow", function() {
          removeReminder('rd_row_1');
        });      
      }
    }
    
    \$(function() {
      \$('#sch').on("swiperight", swiperightHandler);
      
      function swiperightHandler(event) {
        goPrevMonth();
      }
    });
    
    \$(function() {
      \$('#sch').on("swipeleft", swipeleftHandler);
      
      function swipeleftHandler(event) {
        goNextMonth();
      }
    });
                  
    function goPrevMonth() {
      var this_year = parseInt(\$('#what_year').val(), 10);
      var this_month = parseInt(\$('#what_month').val(), 10);
      
      this_month = this_month - 1;
      if (this_month <= 0) {
        this_year = this_year - 1;
        this_month = 12;
      }
      
      \$('#what_year').val(this_year);
      \$('#what_month').val(this_month);
      \$('#frm_sch').submit();      
    }
    
    function goNextMonth() {
      var this_year = parseInt(\$('#what_year').val(), 10);
      var this_month = parseInt(\$('#what_month').val(), 10);
      
      this_month = this_month + 1;
      if (this_month > 12) {
        this_year = this_year + 1;
        this_month = 1;
      }
  
      \$('#what_year').val(this_year);
      \$('#what_month').val(this_month);
      \$('#frm_sch').submit();          
    }
    
    function addEvent(date) {
      date = allTrim(date);
    
      \$('#op').val('A');
      \$('#event_start').val(date);
      \$('#frm_sch').submit();
    }
    
    function readEvent(event_id) {
      \$('#op').val('R');
      \$('#event_id').val(event_id);
      \$('#frm_sch').submit();
    }    
    
    function returnCurrentMonth() {
      \$('#op').val('');
      \$('#what_year').val(0);
      \$('#what_month').val(0);
      \$('#frm_sch').submit();            
    }
    
    function goBack(year, month, op, event_id) {
      window.location.href = "/cgi-pl/tools/scheduler.pl?what_year=" + year + "&what_month=" + month + "&op=" + op + "&event_id=" + event_id;
    }
    
    function removeReminder(rd_row) {
      \$('#reminder_header').hide();
      \$('#' + rd_row).hide();
      \$('#add_reminder_btn').show();
      \$('#has_reminder').val(0);
    }
    
    function addReminder(rd_row) {
      \$('#reminder_header').show();
      \$('#' + rd_row).show();
      \$('#add_reminder_btn').hide();
      \$('#has_reminder').val(1);
    }
    
    function saveEvent() {
      if (dataSetValid() == true) {
        \$('#oper_mode').val('S');
        \$('#frm_sch').submit();
      }
    }
    
    function dataSetValid() {
      var this_event_title = allTrim(\$('#event_title').val());
      var this_event_start = allTrim(\$('#event_start').val());
      var this_event_end = allTrim(\$('#event_end').val());
      var has_reminder = parseInt(\$('#has_reminder'), 10);
      var this_rd_value_1 = parseInt(\$('#rd_value_1'), 10);
      
      if (this_event_title == "") {
        alert("Please input event title before saving");
        \$('#event_title').focus();
        return false;
      }
      
      if (this_event_start == "") {
        alert("Please input event starting date and time before saving");
        \$('#event_start').focus();
        return false;        
      }

      if (this_event_end == "") {
        alert("Please input event ending date and time before saving");
        \$('#event_end').focus();
        return false;        
      }
      
      if (has_reminder >= 1 && this_rd_value_1 <= 0) {
        alert("Reminder value must be a positive integer");
        \$('#rd_value_1').focus();
        return false;
      }
      
      return true;
    }
    
    function editEvent() {
      \$('#op').val('E');
      \$('#frm_sch').submit();
    }
    
    function deleteEvent() {
      if (confirm("Delete this event?")) {
        \$('#op').val('D');
        \$('#oper_mode').val('S');
        \$('#frm_sch').submit();
      }
    }
    
    function schedule() {
      \$('#op').val('L');
      \$('#frm_sch').submit();            
    }
    
    function search() {
      \$('#op').val('S');
      \$('#frm_sch').submit();      
    }
    
    function goSearch() {
      var s_txt = allTrim(\$('#search_phase').val());
      
      if (s_txt != "") {
        \$('#frm_sch').submit();
      }
    }
    
    function searchAgain(s_str) {
      \$('#search_phase').val(s_str);
      \$('#frm_sch').submit();
    }
    
    function goBackSearchResult() {
      \$('#op').val('S');
      \$('#frm_sch').submit();
    }
    
    function goBackEventList() {
      \$('#op').val('L');
      \$('#frm_sch').submit();      
    }
  </script>
__JS
}


sub getCurrentYearAndMonth {
  my ($dbh) = @_;
  my ($sql, $sth, $year, $month);
  
  $sql = <<__SQL;
  SELECT YEAR(CURRENT_TIMESTAMP()) AS year, MONTH(CURRENT_TIMESTAMP()) AS month
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    ($year, $month) = $sth->fetchrow_array();
  }
  else {
    #-- Last resort --#
	  ($year, $month) = (localtime())[5, 4];
	  $month++;
	  $year += 1900;
  }
  $sth->finish;
  
  return ($year, $month);
}


sub getEventsInThisDate {
  my ($dbh, $user_id, $what_date) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT event_id, event_title 
    FROM schedule_event
    WHERE user_id = ?
      AND ? BETWEEN DATE(ev_start) AND DATE(ev_end)
    ORDER BY ev_start
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id, $what_date)) {
    while (my @data = $sth->fetchrow_array()) {     
      push @result, {'event_id' => $data[0], 'event_title' => $data[1]};
    }    
  }
  $sth->finish;
  
  return @result;
}


sub printCalendar {
  my ($dbh, $what_year, $what_month) = @_;
  my ($html, $panel, $month, $first_date, $last_date, $date_pt, $weekday_pt, $offset, $stop_run, $start, $end);
  
  $first_date = $what_year . '-' . sprintf("%02d", $what_month) . '-01';
  $last_date = getLastDateOfMonth($dbh, $first_date);
  $offset = calcStartOffset($dbh, $first_date);
  $month = getMonthName($dbh, $first_date);
  
  $panel = <<__HTML;
  <div data-role="panel" data-position-fixed="true" data-position="right" data-display="overlay" id="sch_func">
    <div data-role="main" class="ui-content">
      <ul data-role="listview">
        <li><a href="javascript:schedule()" data-ajax="false">Event List</a></li>
        <li><a href="javascript:search()" data-ajax="false">Search</a></li>
      </ul>
    </div>
  </div>
__HTML
  
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="event_id" name="event_id" value="">
  <input type=hidden id="event_start" name="event_start" value="">
  
  <div id="sch" data-role="page" style="background-color:$PDA_BG_COLOR">
    $panel
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/tools/select_tools.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>       
      <h1>Schedular</h1>
      <a href="#sch_func" data-icon="bars" class="ui-btn-right" data-ajax="false">Menu</a>      
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed;">
      <thead>
        <tr style="background-color:lightblue">
          <td colspan=7 align=center nowrap>
            <table width=100% cellspacing=0 cellpadding=0 style="table-layout:fixed;">
            <thead>
              <tr>
                <td width=25% align=center>
                  <input type=button onClick="javascript:goPrevMonth();" data-icon="arrow-l" data-iconpos="notext" data-ajax="false">
                </td>  
                <td width=50% align=center><b>$month $what_year</b></td>
                <td width=25% align=center>
                  <input type=button onClick="javascript:goNextMonth();" data-icon="arrow-r" data-iconpos="notext" data-ajax="false">
                </td>
              </tr>
            </thead>
            </table>
          </td>  
        </tr>
        <tr style="background-color:lightblue">
          <td width=14% align=center valign=center>S</td>        
          <td width=14% align=center valign=center>M</td>
          <td width=14% align=center valign=center>T</td>
          <td width=14% align=center valign=center>W</td>
          <td width=14% align=center valign=center>T</td>
          <td width=14% align=center valign=center>F</td>
          <td width=14% align=center valign=center>S</td>
        </tr>                
      </thead>
      
      <tbody>
__HTML
  
  $date_pt = $first_date;
  $start = ($offset == 1)? 1 : 0;    # Specially handle the case which the first day of the month is Sunday.  
  $stop_run = $end = 0;
  while (!$stop_run) {
    $html .= <<__HTML;
    <tr>     
__HTML
    
    for ($weekday_pt = 1; $weekday_pt <= 7; $weekday_pt++) {      
      if ($start && !$end) {
        my $this_day = getDay($dbh, $date_pt);
        my $cell_color = (isToday($date_pt))? 'background-color:#F4F7CE;' : 'background-color:#D0F8FF';
        my @events = getEventsInThisDate($dbh, $user_id, $date_pt);      
        my $all_events = (scalar(@events) > 0)? "<table width=100% cellspacing=0 cellpadding=0 style='table-layout:fixed;'><thead></thead><tbody>" : '';
        my $idx = 1;
        my $link_color = 'black';
        foreach my $rec (@events) {
          my $this_event_id = $rec->{'event_id'} + 0;
          my $this_event_title = (utf8_length($rec->{'event_title'}) > 5)? utf8_substring($rec->{'event_title'}, 0, 5) . '...' : $rec->{'event_title'};
          $link_color = ($idx > 1)? '#003ADE' : 'black';              # blue : black
          my $link = "<a href='javascript:readEvent($this_event_id)' style='font-size: 9px; color:$link_color'>$this_event_title</a>";
          $all_events .= <<__HTML;
          <tr>
            <td valign=top>$link</td>            
          </tr>
          <tr>
            <td height='4px'></td>
          </tr>
__HTML
          $idx++;
          if ($idx > 2) {
            $idx = 1;
          }          
        }
        $all_events .= (scalar(@events) > 0)? "</tbody></table>" : '';
        
        $html .= <<__HTML;
        <td valign=top style="word-wrap:break-word; $cell_color">
          <a href="javascript:addEvent('$date_pt')"><b>$this_day</b></a>
          <br>
          $all_events
          <br>
        </td>
__HTML
        
        $date_pt = gotoNextDate($dbh, $date_pt);        
        if (lastDateHasPassed($dbh, $date_pt, $last_date)) {
          $end = 1;
          $stop_run = 1;
        }
      }
      else {
        if (!$start) {
          #-- A day before the first date of the month --#
          my $pt = $offset - 1;
          if ($pt < 1) {
            $pt = 7;
          }
        
          if ($weekday_pt == $pt) {
            $start = 1;
          }

          $html .= <<__HTML;
          <td>&nbsp;</td>  
__HTML
        }
        
        if ($end) {
          $html .= <<__HTML;
          <td>&nbsp;</td>  
__HTML
        }  
      }
    }
    
    $html .= <<__HTML;
    </tr>     
__HTML
  }  
  
  $html .= <<__HTML;      
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0 style="table-layout:fixed;">
      <thead>
        <tr>
          <td width=50% align=center>
            <input type=button onClick="addEvent()" data-icon="plus" data-ajax="false" value="Add Event">
          </td>
          <td width=50% align=center>
            <input type=button onClick="returnCurrentMonth()" data-icon="refresh" data-ajax="false" value="Today">
          </td>          
        </tr>
      </thead>
      </table>
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub getLastDateOfMonth {
  my ($dbh, $first_date) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT LAST_DAY(?) 
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($first_date)) {
    ($result) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return $result;
}


sub calcStartOffset {
  my ($dbh, $first_date) = @_;
  my ($sql, $sth, $result);
  
  #-- Note: Day of the week index for the date (1 = Sunday, 2 = Monday, ..., 7 = Saturday). --#
  $sql = <<__SQL;
  SELECT DAYOFWEEK(?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($first_date)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = 0;         # Error
  }
  $sth->finish;
  
  return $result;
}


sub getMonthName {
  my ($dbh, $first_date) = @_;
  my ($sql, $sth, $result);

  $sql = <<__SQL;
  SELECT MONTHNAME(?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($first_date)) {
    ($result) = $sth->fetchrow_array();
    $result = substr($result, 0, 3);
  }
  $sth->finish;
  
  return $result;
}


sub getDay {
  my ($dbh, $date) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT DAYOFMONTH(?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($date)) {
    ($result) = $sth->fetchrow_array();
  }
  else {
    #-- Last resort: Assume date format is yyyy-mm-dd --#
    my @parts = split('-', $date);
    $result = $parts[2] + 0;
  }
  $sth->finish;
  
  return $result;
}


sub isToday {
  my ($date) = @_;
  my ($sql, $sth, $diff, $result);
  
  $sql = <<__SQL;
  SELECT DATEDIFF(?, CURRENT_DATE())
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($date)) {
    ($diff) = $sth->fetchrow_array();
    $result = ($diff == 0)? 1 : 0;
  }
  else {
    #-- Assume it is not today --#
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub gotoNextDate {
  my ($dbh, $date) = @_;
  my ($sql, $sth, $result);
  
  $sql = <<__SQL;
  SELECT ADDDATE(?, 1)
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($date)) {
    ($result) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return $result;
}


sub lastDateHasPassed {
  my ($dbh, $date, $last_date) = @_;
  my ($sql, $sth, $diff, $result);
  
  $sql = <<__SQL;
  SELECT DATEDIFF(?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($date, $last_date)) {
    ($diff) = $sth->fetchrow_array();
    $result = ($diff > 0)? 1 : 0;
  }
  else {
    #-- Play safe, assume last date has been passed. --#
    $result = 1;
  }
  $sth->finish;
  
  return $result;
}


sub addNewEvent {
  my ($dbh, $user_id, $event_title, $event_detail, $event_start, $event_end, $reminder_ref) = @_;
  my ($ok, $msg, $event_id, @reminder);
  
  $ok = 1;
  $msg = '';
  
  @reminder = @$reminder_ref;
  
  if (startTransaction($dbh)) {
    ($ok, $msg, $event_id) = addEvent($dbh, $user_id, $event_title, $event_detail, $event_start, $event_end);
    
    if ($ok && scalar(@reminder) > 0) {
      ($ok, $msg) = addReminder($dbh, $event_id, $reminder_ref);
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }    
  }
  else {
    $msg = "Unable to start SQL transaction session, process is aborted.";
    $ok = 0;
  }
    
  return ($ok, $msg);
}


sub addEvent {
  my ($dbh, $user_id, $event_title, $event_detail, $event_start, $event_end) = @_;
  my ($sql, $sth, $ok, $msg, $event_id);
  
  $ok = 1;
  $msg = '';
  $event_id = 0;
  
  $sql = <<__SQL;
  INSERT INTO schedule_event
  (user_id, event_title, event_detail, ev_start, ev_end)
  VALUES
  (?, ?, ?, ?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id, $event_title, $event_detail, $event_start, $event_end)) {
    $msg = "Unable to add event. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
    if ($sth->execute()) {
      ($event_id) = $sth->fetchrow_array();
      if ($event_id <= 0) {
        $msg = "Unable to retrieve the event id by unknown reason";
        $ok = 0;
      }      
    }
    else {
      $msg = "Unable to retrieve the event id. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg, $event_id);
}


sub addReminder {
  my ($dbh, $event_id, $reminder_ref) = @_;
  my ($sql, $sth, $ok, $msg, @reminder);
  
  $ok = 1;
  $msg = '';
  @reminder = @$reminder_ref;
  
  foreach my $rec (@reminder) {
    my $this_rd_value = sprintf("%d", $rec->{'rd_value'} + 0);
    my $this_rd_unit = $rec->{'rd_unit'};
    
    $sql = <<__SQL;
    INSERT INTO schedule_reminder
    (event_id, remind_before, remind_unit, has_informed)
    VALUES
    (?, ?, ?, 0)
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($event_id, $this_rd_value, $this_rd_unit)) {
      $msg = "Unable to add event reminder. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
    
    last if ($ok == 0);
  }
  
  return ($ok, $msg);
}


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


sub printAddEventForm {
  my ($dbh, $event_start, $event_end) = @_;
  my ($html);
  
  if (allTrim($event_start) eq '') {
    $event_start = getCurrentDateTime($dbh, {no_sec => 1});                        # Defined on sm_webenv.pl
  }
  else {
    if (!($event_start =~ /:/)) {
      $event_start = $event_start . ' ' . getCurrentTime($dbh, {no_sec => 1});     # Defined on sm_webenv.pl  
    }
  }
  
  if (allTrim($event_end) eq '') {
    $event_end = setHoursLater($dbh, $event_start, 1);          # Assume event duration is one hour.
  }
  
  #-- Note: Database schema for an event can hold multiple reminders, but here I only implement one reminder for an event. --# 
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="has_reminder" name="has_reminder" value="1">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack($what_year, $what_month)" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Add Event</h1>
    </div>
  
    <div data-role="main" class="ui-content">
      <label for="event_title"><b>Title:</b></label>
      <input type=text id="event_title" name="event_title" value="$event_title" maxlength=256>
      <hr>
      
      <label for="event_start" style="display:inline"><b>Starts:</b></label>
      <input type=text id="event_start" name="event_start" value="$event_start" data-field="datetime" data-startend="start" data-startendelem=".event_end" readonly>
      <label for="event_end" style="display:inline"><b>Ends:</b></label>
      <input type=text id="event_end" name="event_end" value="$event_end" data-field="datetime" data-startend="end" data-startendelem=".event_start" readonly>
      <hr>
      
      <label for="event_detail"><b>Details:</b></label>
      <textarea id="event_detail" name="event_detail"></textarea>
      <hr>
      
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr id="reminder_header">
          <td colspan=3><b>Reminder:</b></td>
        </tr>
      
        <tr id="rd_row_1">
          <td width="20%">
            <input type=number id="rd_value_1" name="rd_value_1" value="30" min="0">
          </td>
          <td>
            <select id="rd_unit_1" name="rd_unit_1">
              <option value="minute">Minutes before</option>
              <option value="hour">Hours before</option>
              <option value="day">Days before</option>
            </select>
          </td>
          <td width="15%" align=center>
            <input type=button id="rd_remove_1" name="rd_remove_1" data-icon="delete" data-iconpos="notext" onClick="removeReminder('rd_row_1')">
          </td>
        </tr>
        
        <tr id="add_reminder_btn">
          <td colspan=3>
            <a href="javascript:addReminder('rd_row_1')">Add Reminder</a>
          </td>
        </tr>
      </tbody>
      </table>
      <hr>
      
      <div id="dt_box"></div>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead></thead>
      <tbody>
        <tr>
          <td width=50% align=center valign=center>
            <input type=button id="save" name="save" data-icon="plus" value="Save Event" onClick="saveEvent()">
          </td>
        </tr>
      </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub setHoursLater {
  my ($dbh, $datetime, $hour) = @_;
  my ($sql, $sth, $time_add, $result);
  
  $time_add = sprintf("%02d", $hour) . ':00:00';
  
  $sql = <<__SQL;
  SELECT ADDTIME("$datetime", "$time_add") AS end_datetime;
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    ($result) = $sth->fetchrow_array();
    my @dt_parts = split(' ', $result);
    my $time = allTrim($dt_parts[1]);
    my @time_parts = split(':', $time);
    $time = $time_parts[0] . ':' . $time_parts[1];
    $result = allTrim($dt_parts[0]) . " $time";    
  }
  else {
    #-- Last resort --#
    my @dt_parts = split(' ', $datetime);
    my $time = allTrim($dt_parts[1]);
    my @time_parts = split(':', $time);
    
    if ($time_parts[0] + $hour <= 23) {
      $time_parts[0] = sprintf("%02d", $time_parts[0] + $hour);
    }
    else {
      $time_parts[0] = "23";
    }
    
    $time = $time_parts[0] . ':' . $time_parts[1];
    $result = allTrim($dt_parts[0]) . " $time";
  }
  $sth->finish;
  
  return $result;
}


sub getEventDetail {
  my ($dbh, $event_id) = @_;
  my ($sql, $sth, %result);
  
  $sql = <<__SQL;
  SELECT event_title, event_detail, DATE_FORMAT(ev_start, '%Y-%m-%d %H:%i') AS ev_start, DATE_FORMAT(ev_end, '%Y-%m-%d %H:%i') AS ev_end
    FROM schedule_event
    WHERE event_id = ?
__SQL
 
  $sth = $dbh->prepare($sql);
  if ($sth->execute($event_id)) {
    my @data = $sth->fetchrow_array();
    %result = ('event_title' => $data[0], 'event_detail' => $data[1], 'ev_start' => $data[2], 'ev_end' => $data[3]);
  }
  $sth->finish;
  
  return %result;
}


sub getReminderListForEvent {
  my ($dbh, $event_id) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT reminder_id, remind_before, remind_unit
    FROM schedule_reminder
    WHERE event_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($event_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'reminder_id' => $data[0], 'remind_before' => $data[1], 'remind_unit' => $data[2]};
    }
  }
  $sth->finish;
  
  return @result;
}
  
sub printReadEventForm {
  my ($event_dtl_ref, $reminder_list_ref) = @_;
  my ($html, $back_link, %event_dtl, @reminder_list);
  
  %event_dtl = %$event_dtl_ref;
  @reminder_list = @$reminder_list_ref;
  
  if ($call_by eq 'event_search') {
    $back_link = "javascript:goBackSearchResult()";
  }
  elsif ($call_by eq 'event_list') {
    $back_link = "javascript:goBackEventList()";
  }
  else {
    $back_link = "javascript:goBack($what_year, $what_month)";
  }
  
  $event_dtl{'event_detail'} =~ s/\n/<br>/g;
  
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="event_id" name="event_id" value="$event_id">
  <input type=hidden id="search_phase" name="search_phase" value="$search_phase">

  <div data-role="page" style="background-color:$PDA_BG_COLOR">  
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="$back_link" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Event</h1>
    </div>
    
    <div data-role="main" class="ui-content">
      <b>Title: </b>$event_dtl{'event_title'}
      <hr>
      <table width=100% cellspacing=0 cellpadding=0>
        <thead></thead>
        <tbody>
          <tr>
            <td width=10% nowrap><b>Start:&nbsp;</b></td>
            <td>$event_dtl{'ev_start'}</td>
          </tr>
          <tr>
            <td><b>End:</b></td>
            <td>$event_dtl{'ev_end'}</td>          
          </tr>
        </tbody>
      </table>
      <hr>
      <b>Details:</b><br>
      $event_dtl{'event_detail'}
      <hr>
__HTML
  
  if (scalar(@reminder_list) > 0) {
    $html .= <<__HTML;
    <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td><b>Reminder:</b></td>
        </tr>
__HTML
    
    foreach my $rec(@reminder_list) {
      my $this_remind_before = $rec->{'remind_before'};
      my $this_remind_unit = ($this_remind_before > 1)? allTrim($rec->{'remind_unit'}) . 's' : allTrim($rec->{'remind_unit'});
      
      $html .= <<__HTML;
      <tr>
        <td>$this_remind_before $this_remind_unit before</td>
      </tr>
__HTML
    }
    
    $html .= <<__HTML;
        </tbody>
      </table>    
__HTML
  }
  else {
    $html .= "<b>No reminder</b>";
  }
    
  $html .= <<__HTML;
      <hr>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0>
        <thead></thead>
        <tbody>
          <tr>
            <td width=50% align=center>
              <input type=button data-icon="edit" value="Edit" onClick="editEvent();">
            </td>
            <td width=50% align=center>
              <input type=button data-icon="delete" value="Delete" onClick="deleteEvent();">
            </td>            
          </tr>
        </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML

  print $html;
}
 

sub deleteEvent {
  my ($dbh, $event_id) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = deleteEventRecord($dbh, $event_id);
    
    if ($ok) {
      ($ok, $msg) = deleteReminder($dbh, $event_id);
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "Unable to start SQL transaction session, event record cannot be deleted.";
    $ok = 0;
  }

  return ($ok, $msg);
}


sub deleteEventRecord {
  my ($dbh, $event_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM schedule_event
    WHERE event_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($event_id)) {
    $msg = "Unable to delete event record. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub deleteReminder {
  my ($dbh, $event_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM schedule_reminder
    WHERE event_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($event_id)) {
    $msg = "Unable to delete event reminder record. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);  
}


sub printEditEventForm {
  my ($event_dtl_ref, $reminder_list_ref) = @_;
  my ($html, $idx, %event_dtl, @reminder_list, @interval);
  
  %event_dtl = %$event_dtl_ref;
  @reminder_list = @$reminder_list_ref;
    
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="event_id" name="event_id" value="$event_id">
  <input type=hidden id="has_reminder" name="has_reminder" value="$has_reminder">  
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack($what_year, $what_month, 'R', $event_id)" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Edit Event</h1>
    </div>
  
    <div data-role="main" class="ui-content">
      <label for="event_title"><b>Title:</b></label>
      <input type=text id="event_title" name="event_title" value="$event_dtl{'event_title'}" maxlength=256>
      <hr>
      
      <label for="event_start" style="display:inline"><b>Starts:</b></label>
      <input type=text id="event_start" name="event_start" value="$event_dtl{'ev_start'}" data-field="datetime" data-startend="start" data-startendelem=".event_end" readonly>
      <label for="event_end" style="display:inline"><b>Ends:</b></label>
      <input type=text id="event_end" name="event_end" value="$event_dtl{'ev_end'}" data-field="datetime" data-startend="end" data-startendelem=".event_start" readonly>
      <hr>
      
      <label for="event_detail"><b>Details:</b></label>
      <textarea id="event_detail" name="event_detail">$event_dtl{'event_detail'}</textarea>
      <hr>
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr id="reminder_header">
          <td colspan=3><b>Reminder:</b></td>
        </tr>
__HTML

  push @interval, {'opt_value' => 'minute', 'opt_desc' => 'Minutes before'};
  push @interval, {'opt_value' => 'hour', 'opt_desc' => 'Hours before'};
  push @interval, {'opt_value' => 'day', 'opt_desc' => 'Days before'};
  #-- Note: Although currently users can just put one reminder to an event, it may be enhanced later to let users add multiple reminders. --#  
  $idx = 1;
  foreach my $rec (@reminder_list) {
    my $this_rd_id = $rec->{'reminder_id'} + 0;
    my $this_rd_value = $rec->{'remind_before'} + 0;
    my $this_rd_unit = $rec->{'remind_unit'}; 
    
    my $this_options = '';
    foreach my $opt (@interval) {
      my $this_opt_value = $opt->{'opt_value'};
      my $this_opt_desc = $opt->{'opt_desc'};
      my $selected = ($this_opt_value eq $this_rd_unit)? 'selected' : '';
      $this_options .= "<option value='$this_opt_value' $selected>$this_opt_desc</option>";
    }
    
    $html .= <<__HTML;      
        <tr id="rd_row_$idx">
          <td width="20%">
            <input type=hidden id="rd_id_$idx" name="rd_id_$idx" value="$this_rd_id">
            <input type=number id="rd_value_$idx" name="rd_value_$idx" value="$this_rd_value" min="0">
          </td>
          <td>
            <select id="rd_unit_$idx" name="rd_unit_$idx">
              $this_options
            </select>
          </td>
          <td width="15%" align=center>
            <input type=button id="rd_remove_$idx" name="rd_remove_$idx" data-icon="delete" data-iconpos="notext" onClick="removeReminder('rd_row_$idx')">
          </td>
        </tr>
__HTML

    $idx++;
  }
  
  if (scalar(@reminder_list) == 0) {
    $html .= <<__HTML;      
        <tr id="rd_row_1">
          <td width="20%">
            <input type=number id="rd_value_1" name="rd_value_1" value="30" min="0">
          </td>
          <td>
            <select id="rd_unit_1" name="rd_unit_1">
              <option value="minute">Minutes before</option>
              <option value="hour">Hours before</option>
              <option value="day">Days before</option>
            </select>
          </td>
          <td width="15%" align=center>
            <input type=button id="rd_remove_1" name="rd_remove_1" data-icon="delete" data-iconpos="notext" onClick="removeReminder('rd_row_1')">
          </td>
        </tr>
__HTML
  }
  
  $html .= <<__HTML;
        <tr id="add_reminder_btn">
          <td colspan=3>
            <a href="javascript:addReminder('rd_row_1')">Add Reminder</a>
          </td>
        </tr>
      </tbody>
      </table>    
      <hr>
      
      <div id="dt_box"></div>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center>
            <input type=button data-icon="plus" value="Update Event" onClick="saveEvent()">
          </td>
        </tr>
      </tbody>
      </table>
    </div>
  </div>
  </form>  
__HTML
  
  print $html;
}


sub updateEvent {
  my ($dbh, $event_id, $event_title, $event_detail, $event_start, $event_end, $reminder_ref) = @_;
  my ($ok, $msg);

  $ok = 1;
  $msg = '';

  if (startTransaction($dbh)) {
    ($ok, $msg) = modifyEvent($dbh, $event_id, $event_title, $event_detail, $event_start, $event_end);
    
    if ($ok) {
      ($ok, $msg) = modifyEventReminder($dbh, $event_id, $reminder_ref);
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "Unable to start SQL transaction session to update event.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub modifyEvent {
  my ($dbh, $event_id, $event_title, $event_detail, $event_start, $event_end) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE schedule_event
    SET event_title = ?,
        event_detail = ?,
        ev_start = ?,
        ev_end = ?
    WHERE event_id = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($event_title, $event_detail, $event_start, $event_end, $event_id)) {
    $msg = "Unable to update event. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub modifyEventReminder {
  my ($dbh, $event_id, $reminder_ref) = @_;
  my ($ok, $msg, $sql, $sth, @reminder);

  $ok = 1;
  $msg = '';
  
  #-- Step 1: Remove all event reminders first --#
  $sql = <<__HTML;
  DELETE FROM schedule_reminder
    WHERE event_id = ?
__HTML

  $sth = $dbh->prepare($sql);
  if (!$sth->execute($event_id)) {
    $msg = "Unable to remove old event reminder record(s). Error: " .$sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  if ($ok) {
    #-- Step 2: Create reminder(s) of the event --#
    @reminder = @$reminder_ref;
    foreach my $rec (@reminder) {
      my $this_rd_value = $rec->{'rd_value'} + 0;
      my $this_rd_unit = $rec->{'rd_unit'};
      
      #-- Note: Since 'has_informed' flag is put as 0, it means the reminder may be triggered again, even --#
      #--       informed message has been sent before.                                                    --#
      $sql = <<__SQL;
      INSERT INTO schedule_reminder
      (event_id, remind_before, remind_unit, has_informed)
      VALUES
      (?, ?, ?, 0)
__SQL

      $sth = $dbh->prepare($sql);
      if (!$sth->execute($event_id, $this_rd_value, $this_rd_unit)) {
        $msg = "Unable to renew event reminder record. Error: " . $sth->errstr;
        $ok = 0;
      }
      $sth->finish;
      
      last if (!$ok);
    }
  }

  return ($ok, $msg);  
}


sub searchEvents {
  my ($dbh, $user_id, $search_phase) = @_;
  my ($sql, $sth, %events, @keywords, @buffer, @result);
  
  @keywords = split(';', $search_phase);
  
  foreach my $this_keyword (@keywords) {
    $this_keyword = allTrim($this_keyword);
    
    $sql = <<__SQL;
    SELECT event_id, event_title, DATE_FORMAT(ev_start, '%Y-%m-%d %H:%i') AS ev_start
      FROM schedule_event
      WHERE user_id = ?
        AND (event_title LIKE '%$this_keyword%'
         OR event_detail LIKE '%$this_keyword%')
      ORDER BY ev_start DESC  
__SQL
    
    $sth = $dbh->prepare($sql);
    if ($sth->execute($user_id)) {
      while (my @data = $sth->fetchrow_array()) {
        my $this_event_id = $data[0] + 0;
        if ($events{$this_event_id} + 0 != 1) {
          #-- Avoid event duplication in search result --#
          push @buffer, {'event_id' => $data[0], 'event_title' => $data[1], 'ev_start' => $data[2]};
          $events{$this_event_id} = 1;
        }
      }
    }
    $sth->finish;    
  }
  
  #-- Sort in reverse order, the newest event go first --#
  @result = sort {$b->{'ev_start'} cmp $a->{'ev_start'}} @buffer;
  
  return @result;
}


sub printSearchResult {
  my ($search_records_ref) = @_;
  my ($html, @search_records);
  
  @search_records = @$search_records_ref;
  
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="search_phase" name="search_phase" value="$search_phase">  
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="event_id" name="event_id" value="0">
  <input type=hidden id="call_by" name="call_by" value="event_search">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:searchAgain('')" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Search Result</h1>
      <a href="javascript:goBack($what_year, $what_month)" data-icon="calendar" style="ui-btn-right" data-ajax="false">Calender</a>
    </div>

    <div data-role="content" style="ui-content">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead>
        <tr style="background-color:lightblue">
          <td width=20% align=center><b>Date</b></td>
          <td align=center><b>Event</b></td>        
        </tr>
      </thead>
      
      <tbody>
__HTML

  if (scalar(@search_records) > 0) {
    foreach my $rec (@search_records) {
      my $this_event_id = $rec->{'event_id'} + 0;
      my $this_event_title = $rec->{'event_title'};
      my $this_ev_start = $rec->{'ev_start'};
      my $this_target = "javascript:readEvent($this_event_id)";
      
      $html .= <<__HTML;
      <tr style="background-color:lightyellow">
        <td align=center nowrap><a href="$this_target">$this_ev_start</a></td>
        <td><a href="$this_target">$this_event_title</a></td>
      </tr>
__HTML
    }
  }
  else {
    $html .= <<__HTML;
    <tr style="background-color:lightgray">
      <td colspan=2>Nothing is found</td>
    </tr>
__HTML
  }

  $html .= <<__HTML;
      </tbody>
      </table>
    </div>
  </div>
  </form>  
__HTML
  
  print $html;
}


sub printSearchForm {
  my ($html);
  
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">

  <div data-role="page" style="background-color:$PDA_BG_COLOR;">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack($what_year, $what_month)" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Event Search</h1>      
    </div>
  
    <div data-role="content" style="ui-content">
      <!-- Note: ASCII semicolon is NOT equal to semicolon in other languages or UTF-8 encoded semicolon -->
      <label for="search_phase"><b>Search keyword(s) separated by semicolon:</b></label>
      <input type=text id="search_phase" name="search_phase">
      <br>
      <input type=button id="go" name="go" value="Go" data-icon="search" onClick="goSearch()">
    </div>
  </div>
  </form>
__HTML

  print $html;
}


sub getEventList {
  my ($dbh, $user_id) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT event_id, event_title, DATE_FORMAT(ev_start, '%Y-%m-%d %H:%i') AS ev_start,
         CASE
           WHEN ev_start < CURRENT_TIMESTAMP() THEN 1
           ELSE 0
         END AS has_passed
    FROM schedule_event
    WHERE user_id = ?
    ORDER BY ev_start
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'event_id' => $data[0], 'event_title' => $data[1], 'ev_start' => $data[2], 'has_passed' => $data[3]};
    }
  }
  
  return @result;
}


sub printEventList {
  my ($event_list_ref) = @_;
  my ($html, @event_list);
  
  @event_list = @$event_list_ref;
  
  $html = <<__HTML;
  <form id="frm_sch" name="frm_sch" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="what_year" name="what_year" value="$what_year">
  <input type=hidden id="what_month" name="what_month" value="$what_month">
  <input type=hidden id="event_id" name="event_id" value="0">
  <input type=hidden id="call_by" name="call_by" value="event_list">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack($what_year, $what_month)" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Event List</h1>
    </div>
  
    <div data-role="content" style="ui-content">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead>
        <tr style="background-color:lightblue">
          <td width=20% align=center><b>Date</b></td>
          <td align=center><b>Event</b></td>
        </tr>
      </thead>
      
      <tbody>
__HTML

  if (scalar(@event_list) > 0) {
    my $first_active_event_found = 0;
    
    foreach my $rec (@event_list) {
      my $this_event_id = $rec->{'event_id'} + 0;
      my $this_event_title = $rec->{'event_title'};
      my $this_ev_start = $rec->{'ev_start'};
      my $this_has_passed = $rec->{'has_passed'} + 0;
      my $tr_bg_color = ($this_has_passed)? 'lightgray' : 'lightyellow';
      my $tr_id = '';
      
      if (!$this_has_passed && !$first_active_event_found) {
        $tr_id = "id=first_active_event";
        $first_active_event_found = 1;
      }
      
      $html .= <<__HTML;
      <tr $tr_id style="background-color:$tr_bg_color">
        <td align=center nowrap><a href="javascript:readEvent($this_event_id)">$this_ev_start</a></td>
        <td><a href="javascript:readEvent($this_event_id)">$this_event_title</a></td>
      </tr>
__HTML
    }
  }
  else {
    $html .= <<__HTML;
    <tr style="background-color:lightgray">
      <td colspan=2>No event record</td>
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
  </div>
  </form>  
__HTML
  
  print $html;
}