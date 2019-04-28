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
# Program: /www/perl_lib/sm_webenv.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-17      DW              Library functions used for web application
#                                               environment.
# V1.0.01       2018-08-08      DW              Ensure UTF-8 data has been decoded before
#                                               pass to function 'sendOutGmail'.
# V1.0.02       2018-08-27      DW              Implement CGI file upload related functions.
# V1.0.03       2018-08-30      DW              Add thumbnail image creation function.
# V1.0.04       2018-10-12      DW              Modify function sendOutGmail to handle required 
#                                               data missing as connection_mode is 1.
# V1.0.05       2018-11-23      DW              Fix a bug on function utf8_substring.
# V1.0.06       2018-12-10      DW              Add function 'printFreeHeader' for those
#                                               programs valid login user is not required.
#                                               For example, function 'request to join'.
# V1.0.07       2019-02-04      DW              Extend short upload file name to avoid hackers
#                                               guess it easily.
# V1.0.08       2019-04-28      DW              Add new function 'sessionExist'.
##########################################################################################

use strict;
use CGI qw/:standard/;
use DBI;
use utf8;
use Path::Class qw/file/;
use Encode;
use URI::Escape;
use Email::Sender::Simple qw/try_to_sendmail/;
use Email::MIME;
use Email::MIME::Creator;
use Email::Sender::Transport::SMTP::TLS;
use HTTP::BrowserDetect;
use File::Basename;
use File::Copy;
use Image::Magick;
require "sm_user.pl";
require "sm_db.pl";

BEGIN {
  use CGI::Carp qw(fatalsToBrowser);
}

#-- Define global variables --#
our $COOKIE_PDA = 'PDA_USER';
our $COOKIE_MSG = 'MSG_USER';
our $COMP_NAME = 'PDA Tools Corp.';
our $ITN_FILE_PATH = '/www/itnews/data';
our $ITN_TN_PATH = '/www/itnews/data/thumbnail';         
our $PDA_FILE_PATH = '/www/pdatools/data';
our $PDA_IMG_PATH = '/www/pdatools/images';
our $PDA_TOOLS_PATH = '/www/pdatools/cgi-pl/tools';
our $PDA_BG_COLOR = '#E0F4FB';
our $PRINTHEAD;

my $utf_8 = q{
    [\x00-\x7F]                                                 # One-byte range
  | [\xC2-\xDF][\x80-\xBF]                                      # Two-byte range
  | \xE0[\xA0-\xBF][\x80-\xBF]                                  # Three-byte range
  | [\xE1-\xEF][\x80-\xBF][\x80-\xBF]                           # Three-byte range
  | \xF0[\x90-\xBF][\x80-\xBF][\x80-\xBF]                       # Four-byte range
  | [\xF1-\xF7][\x80-\xBF][\x80-\xBF][\x80-\xBF]                # Four-byte range
  | \xF8[\x88-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF]            # Five-byte range
  | [\xF9-\xFB][\x80-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF]     # Five-byte range
  | \xFC[\x84-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF] # Six-byte range
  | \xFD[\x80-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF][\x80-\xBF] # Six-byte range
};

sub preventXSSCodeEmbed {
  my ($string) = @_;
  
  if ($string =~ /<script>/i) {
    $string =~ s/<script>//gi;
  }

  if ($string =~ /<\/script>/i) {
    $string =~ s/<\/script>//gi;
  }  
  
  $string =~ s/<script//gi;
  $string =~ s/<\/script//gi;
  $string =~ s/\%3Cscript//gi;
  $string =~ s/\%3Escript//gi;		
  $string =~ s/<iframe//gi;
  $string =~ s/<\/iframe//gi;
  $string =~ s/\%3Ciframe//gi;  

  return $string;
}


sub paramAntiXSS {
  my ($param_name) = @_;
  
  return preventXSSCodeEmbed(param($param_name));       
}


sub parameter {
	my (@var) = @_;
	my (%temp);
  
	for(my $i = 0; $i < scalar(@var); $i++) {
    $temp{$var[$i]} = preventXSSCodeEmbed(param($var[$i]));      
	}
  
	return %temp;
}


sub leftTrim {
  my ($strToTrim) = @_;

  if ($strToTrim eq undef) {
	  $strToTrim = '';
	}
	else {
    $strToTrim =~ s/^\s+//;  
	}	

  return $strToTrim;
}


sub rightTrim {
  my ($strToTrim) = @_;

  if ($strToTrim eq undef) {
	  $strToTrim = '';
	}
  else { 
    $strToTrim =~ s/\s+$//;  
	}	
  
  return $strToTrim;
}


sub allTrim {
  my $strToTrim = shift;

  return leftTrim(rightTrim($strToTrim));
}


sub back {
  print <<__JS;
  <script language="javascript" type="text/javascript">
    history.go(-1);
  </script>
__JS
}


sub redirectTo {
  my ($go_url) = @_;
  
  if (allTrim($go_url) ne '') {
    print <<__JS;
    <script language="javascript" type="text/javascript">
      window.location.href = "$go_url";
    </script>
__JS
  }
}


sub detectClientDevice {
  my ($user_agent_str, $ua, $device_type, $device_name);
  
  $user_agent_str = allTrim($ENV{'HTTP_USER_AGENT'});
  
  if ($user_agent_str ne '') {
    $ua = HTTP::BrowserDetect->new($user_agent_str);
    
    if ($ua) {
      if ($ua->device() ne undef) {
        $device_name = $ua->device();

        if ($ua->mobile()) {
          $device_type = 'mobile';
        }
        elsif ($ua->tablet()) {
          $device_type = 'tablet';     
        }        
      }
      else {
        $device_name = 'pc';        # Note: Include laptop computer.
        $device_type = 'desktop';
      }
    }
  }
  
  return ($device_type, $device_name);
}


sub printCSS {
  my ($what, $options_ref) = @_;
  my ($t_bgcolor, $t_title1, $t_title2, $t_text, $t_link, $t_linkbg, $t_menu1, $t_menu2, $t_menu_text, $t_menu_link, $t_menu_linkbg);
  my ($t_input_text, $t_input_bg, $t_t_title, $t_t_title_bg, $t_t_content, $t_t_content_bg, $t_t_title2, $t_t_title_bg2, $t_t_content2);
  my ($t_t_content_bg2, $css_str, $device_type, $font_size, $heading_font_size, $comp_font_size, $footer_font_size, %options);

  if (ref $options_ref eq 'HASH' && $options_ref ne undef) {
    %options = %$options_ref;  
  }
  else {
    %options = ();
  }
  
	unless($t_bgcolor){$t_bgcolor = ($what eq $COOKIE_PDA)? "#E0F4FB" : "white";}
	unless($t_title1){$t_title1 = "#08088A";}
	unless($t_title2){$t_title2 = "deepskyblue";}
	unless($t_text){$t_text = "dimgray";}
	unless($t_link){$t_link = "limegreen";}
	unless($t_linkbg){$t_linkbg = "greenyellow";}
	unless($t_menu1){$t_menu1 = "dimgray";}
	unless($t_menu2){$t_menu2 = "dimgray";}
	unless($t_menu_text){$t_menu_text = "#555555";}
	unless($t_menu_link){$t_menu_link = "#555555";}
	unless($t_menu_linkbg){$t_menu_linkbg = "#555555";}
	unless($t_input_text){$t_input_text = "dimgray";}
	unless($t_input_bg){$t_input_bg = "gainsboro";}
	unless($t_t_title){$t_t_title = "dimgray";}
	unless($t_t_title_bg){$t_t_title_bg = "powderblue";}
	unless($t_t_content){$t_t_content = "dimgray";}
	unless($t_t_content_bg){$t_t_content_bg = "azure";}
	unless($t_t_title2){$t_t_title2 = "#FFFFFF";}
	unless($t_t_title_bg2){$t_t_title_bg2 = "#A4A5C4";}
	unless($t_t_content2){$t_t_content2 = "#000000";}
	unless($t_t_content_bg2){$t_t_content_bg2 = "#AAAAAA";}

  ($device_type) = detectClientDevice();
  $font_size = ($device_type eq 'desktop')? '9pt' : (($device_type eq 'tablet')? '18pt' : '36pt');
  $heading_font_size = ($device_type eq 'desktop')? '12pt' : (($device_type eq 'tablet')? '22pt' : '40pt');
  $comp_font_size = ($device_type eq 'desktop')? '10pt' : (($device_type eq 'tablet')? '20pt' : '38pt');
  $footer_font_size = ($device_type eq 'desktop')? '7pt' : (($device_type eq 'tablet')? '16pt' : '20pt');
  
	$css_str = <<__STYLE;
  <STYLE TYPE="text/css">
  <!-- 
  a:link        {text-decoration: none; color:$t_link;}
  a:active      {text-decoration: none; color:$t_link;}
  a:visited     {text-decoration: none; color:$t_link;}
  a:hover       {color: red; text-decoration: none; background:$t_linkbg;}
  BODY          {background-color:$t_bgcolor; font-family:arial; color:$t_text}
  input         {font: $font_size Arial;}
  select        {font: $font_size Arial; color:$t_input_text; background-color: $t_input_bg;}
  textarea      {font: $font_size Arial; color:$t_input_text; background-color: $t_input_bg;}
  .heading      {font: $heading_font_size Arial;}
  .company      {font: $comp_font_size Arial;}
  .footer       {font: $footer_font_size Arial;} 
  .title1	      {color:$t_title1; font-size: $font_size;}
  .title2       {color:$t_title2; font-size: $font_size;}
  .table        {font-size: $font_size}
  .textbox      {color:$t_input_text; background-color: $t_input_bg;}
  .t_title      {background-color: $t_t_title_bg; color: $t_t_title; font-size: $font_size; }
  .t_title2     {background-color: $t_t_title_bg2; color: $t_t_title2; font-size: $font_size;}
  .t_text       {color: $t_t_title; font-size: $font_size}
  .t_content    {background-color: $t_t_content_bg; color: $t_t_content; font-size: $font_size;}
  .t_content2   {background-color: $t_t_content_bg2; color: $t_t_content2; font-size: $font_size;}
  .menu_title1  {color: $t_menu1;}
  .menu_title2  {color: $t_menu2;}
  .menu_text    {color: $t_menu_text;}
  .menu_link    {color: $t_menu_link;font-size: $font_size;}
  .t_err	      {background-color: #AA9D9A; color: #000000;}
  .readonly     {color:#000000; background-color: #CCCCCC;}
  .row_alert    {background-color: #FEF536; color: #000000;}
  .row_error    {background-color: #D43037; color: #000000;}
  -->
  </STYLE>
__STYLE

  #-- If '$oper_mode' eq 'S' (screen only mode), just return CSS as string and don't print CSS to STDOUT. --#
  if (uc($options{'oper_mode'}) ne 'S') {
    print $css_str;
  }
  
  return $css_str;
}


sub printMoreJQueryMobileCSS {
  my ($options_ref) = @_;
  my ($css_str, $hide_body_css,  %options);

  if (ref $options_ref eq 'HASH' && $options_ref ne undef) {
    %options = %$options_ref;  
  }
  else {
    %options = ();
  }
  
  $hide_body_css = ($options{'hide_body'})? "body {display: none}" : "";
  
  $css_str = <<__STYLE;
  <style type="text/css">
  .noshadow * {
		-webkit-box-shadow: none !important;
		-moz-box-shadow: none !important;
		box-shadow: none !important;
	}
  
  $hide_body_css
  
	form.ui-mini .ui-field-contain fieldset.ui-controlgroup legend small {
		color: #666;
	}  
  </style>
__STYLE
  
  #-- If '$oper_mode' eq 'S' (screen only mode), just return CSS as string and don't print CSS to STDOUT. --#
  if (uc($options{'oper_mode'}) ne 'S') {
    print $css_str;
  }
  
  return $css_str;  
}


sub alert {
  my ($msg) = @_;
  
  $msg = uri_escape($msg);
  
  print <<__JS;  
  <script "text/javascript">
    alert(unescape("$msg"));
  </script>
__JS
}


sub _getCurrentTimestamp {
  my ($dbh) = @_;
  my ($sql, $sth, $result);
  
  if ($dbh) {
    $sql = "SELECT CURRENT_TIMESTAMP() AS time";
    $sth = $dbh->prepare($sql);
    $sth->execute();
    ($result) = $sth->fetchrow_array();
    $sth->finish();
    $result = allTrim($result);
  }
  else {
    $result = '';
  }
  
  return $result;
}


sub _generateRandomStr {
  my ($option, $max_len) = @_;
  my ($max_ascii_value, $char, $stop_run, $cnt, $result, @ascii_list);
  
  #-- Valid options are: 'A' = Alphanumeric, 'N' = Numeric only, 'S' = English characters only. --#  
  $option = (allTrim($option) eq '')? 'A' : uc($option);
  $max_len = ($max_len + 0 <= 0)? 10 : $max_len;
  
  if ($option eq 'N') {
    for (my $i = 48; $i <= 57; $i++) {
      push @ascii_list, $i;      
    }
    
    $max_ascii_value = 57;
  }
  elsif ($option eq 'S') {
    for (my $i = 65; $i <= 90; $i++) {
      push @ascii_list, $i;      
    }
    
    for (my $i = 97; $i <= 122; $i++) {
      push @ascii_list, $i;      
    }
    
    $max_ascii_value = 122;
  }
  else {
    for (my $i = 48; $i <= 57; $i++) {
      push @ascii_list, $i;      
    }

    for (my $i = 65; $i <= 90; $i++) {
      push @ascii_list, $i;      
    }
    
    for (my $i = 97; $i <= 122; $i++) {
      push @ascii_list, $i;      
    }
    
    $max_ascii_value = 122;
  }
  
  $result = '';
  $stop_run = $cnt = 0;
  while (!$stop_run) {
    my $this_ascii = sprintf("%.0f", rand($max_ascii_value));
    my $valid_value = 0;
    
    foreach my $ascii (@ascii_list) {
      if ($ascii == $this_ascii) {
        $valid_value = 1;
      }
      last if ($valid_value);
    }
    
    if ($valid_value) {
      $char = chr($this_ascii);
      $result .= $char;
    }
    
    if (length($result) >= $max_len) {
      $stop_run = 1;
    }
    
    if ($cnt >= 90000) {
      $stop_run = 1;
    }
    else {
      $cnt++;  
    }    
  }
  
  return $result;
}


sub getSiteDNS {
  my ($dbh, $type) = @_;
  my ($sql, $sth, $site_type, $site_dns);
  
  $type = uc(allTrim($type));
  
  if ($type eq 'D' || $type eq 'M') {
    $site_type = ($type eq 'D')? 'DECOY' : 'MESSAGE';
    
    $sql = <<__SQL;
    SELECT site_dns
      FROM sites
      WHERE site_type = ?
        AND status = 'A'
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($site_type)) {
      ($site_dns) = $sth->fetchrow_array();
    }
    else {
      $site_dns = '';
    }
    $sth->finish;
  }
  else {
    $site_dns = '';
  }
  
  return $site_dns;
}


sub getSysEmailSender {
  my ($dbh) = @_;
  my ($sql, $sth, $email, $m_user, $m_pass, $smtp_server, $port, $cnt, $rows, $idx, $max_cnt, $stop_run, @senders);
  
  if ($dbh) {
    #-- Step 1: Get all active email server records --#
    $sql = <<__SQL;
    SELECT email, m_user, m_pass, smtp_server, port
      FROM sys_email_sender
      WHERE status = 'A'
__SQL

    $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my @data = $sth->fetchrow_array()) {
      push @senders, {'email' => $data[0], 'm_user' => $data[1], 'm_pass' => $data[2], 'smtp_server' => $data[3], 'port' => $data[4]};
    }
    $sth->finish;

    $rows = scalar(@senders);
    
    #-- Default values (Assume it has at least one email sender account defined) --#
    $email = $senders[0]->{'email'};
    $m_user = $senders[0]->{'m_user'};
    $m_pass = $senders[0]->{'m_pass'};
    $smtp_server = $senders[0]->{'smtp_server'};
    $port = $senders[0]->{'port'};      
    
    if ($rows > 1) {
      $max_cnt = 0;
      $stop_run = 0;
      while (!$stop_run) {
        $cnt = sprintf("%.0f", rand($rows));
        if ($cnt >= 1 && $cnt <= $rows) {
          $idx = $cnt - 1;
          $email = $senders[$idx]->{'email'};
          $m_user = $senders[$idx]->{'m_user'};
          $m_pass = $senders[$idx]->{'m_pass'};
          $smtp_server = $senders[$idx]->{'smtp_server'};
          $port = $senders[$idx]->{'port'};                
          $stop_run = 1;
        }
        
        if (!$stop_run) {
          $max_cnt++;
          if ($max_cnt > 10) {
            $stop_run = 1;
          }          
        }
      }
    }
  }
  
  return ($email, $m_user, $m_pass, $smtp_server, $port);
}


sub sendOutGmail {
  my ($from_mail, $to_mail, $from_user, $from_pass, $smtp_server, $port, $subject, $body) = @_;
  my ($ok, $msg, $ready_to_go, $email);
  
  $ok = 1;
  $msg = '';
  
  if ($from_mail ne '' && $to_mail ne '' && $smtp_server ne '' && $port > 0) {
    $ready_to_go = 1;
  }
  else {
    $ready_to_go = 0;
  }
  
  if ($ready_to_go) {
    $email = Email::MIME->create(
      header => [
          From    => $from_mail,
          To      => $to_mail,
          Subject => Encode::encode('MIME-Header-UTF_8', $subject),
      ],
      parts => [
          # Mail body (UTF-8)
          Email::MIME->create(
              attributes => {
                  content_type => 'text/plain',
                  charset      => 'utf8',
                  encoding     => '8bit',                
              },
              body_str => $body,
          ),
      ],
    );
  
    try_to_sendmail(
      $email,
      {   
          transport => Email::Sender::Transport::SMTP::TLS->new(
              host     => $smtp_server,
              port     => $port,
              username => $from_user,
              password => $from_pass,
          )
      }
    ) or do {
      $msg = "Mail sending is failure.\n";
      $ok = 0;    
    };
  }
  
  return ($ok, $msg);
}


sub selectSiteForVisitor {
  my ($dbh) = @_;
  my ($sql, $sth, $cnt, $rows, $stop_run, $idx, $max_cnt, $result, @sites);
  
  #-- Default value --#
  $result = 'https://www.microsoft.com';
  
  $sql = <<__SQL;
  SELECT site_url
    FROM decoy_sites
__SQL
  
  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (my ($this_site) = $sth->fetchrow_array()) {
    push @sites, {'url' => $this_site};
  }
  $sth->finish;  
  $rows = scalar(@sites);
  
  if ($rows > 0) {
    $stop_run = 0;
    while (!$stop_run) {
      $cnt = sprintf("%.0f", rand($rows));      
      if ($cnt >= 1 && $cnt <= $rows) {
        $idx = $cnt - 1;
        $result = $sites[$idx]->{'url'};
        $stop_run = 1;
      }
        
      if (!$stop_run) {
        $max_cnt++;
        if ($max_cnt >= 2000) {
          $stop_run = 1;
        }
      }
    }
  }
  
  return $result;
}


sub setSessionValidTime {
  my ($dbx, $sql, $sth, $year, $month, $day, $hour, $min, $sec, $session_period, $session_time_limit, @days_in_month);

  $dbx = dbconnect($COOKIE_MSG);        # Note: session_period is on msgdb only.  
  $session_time_limit = '';
  
  if ($dbx) {
    $session_period = allTrim(getSysSettingValue($dbx, 'session_period'));
    if ($session_period eq '') {
      #-- Default session valid period is 2 hours --#
      $session_period = '02:00:00';
    }
           
    $sql = <<__SQL;
    SELECT ADDTIME(CURRENT_TIMESTAMP(), "$session_period") AS time_limit;
__SQL

    $sth = $dbx->prepare($sql);
    if ($sth->execute()) {
      ($session_time_limit) = $sth->fetchrow_array(); 
    }
    $sth->finish;
    
    dbclose($dbx);
  }

  if ($session_time_limit eq '') {
    #-- It is the last resort --#
	  ($year, $month, $day, $hour, $min, $sec) = (localtime())[5, 4, 3, 2, 1, 0];
	  $month++;
	  $year += 1900;
	  (@days_in_month) = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
	  if (isLeapYear($year)) {
		  $days_in_month[2] = 29;
	  }

    #-- Default session valid period is 2 hours --#
	  $hour += 2;
	  if ($hour >= 24) {$hour -= 24; $day++;}
	  if ($day > $days_in_month[$month]) {$day -= $days_in_month[$month]; $month++;}
	  if ($month > 12) {$month -= 12; $year++;}
    
    $month = sprintf("%02d", $month);
    $day = sprintf("%02d", $day);
    $hour = sprintf("%02d", $hour);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    
    $session_time_limit = "$year-$month-$day $hour:$min:$sec";   
  }
	
	return $session_time_limit;	
}


# Find leap years.  (returns 1=leap or 0=normal)
#
# Works on julian/gregorian, with english-changeover.  
# Doesn't work before julian (i.e. before about AD100)
sub isLeapYear() { 
	my ($Year) = @_;
	
	#Every 400 years in gregorian is leap, but in julian it isn't.
	if(($Year % 400) == 0)
	{		
		if ($Year < 1752)
		{
			return(0);
		}
		else
		{
			return(1);
		}
	}	
	else
	{
		#Other centuries are not leap
		if(($Year % 100) == 0)
		{
			return(0);
		}
		else
		{
			#Normal system: every 4th year is leap
			if(($Year % 4) == 0)
			{
				return(1);
			}
			else
			{
				return(0);
			}
		}
	}
}


sub printFreeHeader {
  my ($title) = @_;
  my ($html);
  
  print header(-type => 'text/html', -charset => 'utf-8', -cache-control => 'no-cache');
  
  $html = <<__HTML;
  <!DOCTYPE html>
  <html>
    <head>
      <title>$title</title>
      <meta name="viewport" content="minimum-scale=1.0, width=device-width, maximum-scale=1.0, initial-scale=1.0, user-scalable=no">      
    </head>
    <body style="width:auto;">
__HTML
  
  print $html;
}


sub printHead {
  my ($cookie_name, $options_ref) = @_;
  my ($cookie, $ui_ref, $new_time_limit, $site_dns, %user_info, %options);

  if (ref $options_ref eq 'HASH' && $options_ref ne undef) {
    %options = %$options_ref;  
  }
  else {
    %options = ();
  }
    
  if (sessionAlive($cookie_name)) {               # Defined on sm_user.pl
    $new_time_limit = setSessionValidTime();      # Extend session time limit. 
    $ui_ref = getSessionInfo($cookie_name);       # Defined on sm_user.pl
    %user_info = %$ui_ref;
    $user_info{'VALID'} = $new_time_limit; 
    $cookie = cookie(-name => $cookie_name, -value => \%user_info, -path => '/', -expires => '+2d', -secure => 1);
    print header(-type => 'text/html', -charset => 'utf-8', -cookie => $cookie, -cache-control => 'no-cache');
    
    print <<__HTML;
    <!DOCTYPE html>
    <html>
    <head>
      <title>$options{'title'}</title>
      <meta name="viewport" content="minimum-scale=1.0, width=device-width, maximum-scale=1.0, initial-scale=1.0, user-scalable=no">      
__HTML
    
    if ($cookie_name eq $COOKIE_MSG) {
      #printMoreJQueryMobileCSS($options_ref);
      
      print <<__HTML;
      </head>
      <body style="width:auto;">
__HTML
    }
    else {
      printCSS($cookie_name, $options_ref);
    
      print <<__HTML;
      </head>    
      <body leftmargin="20" topmargin="20" marginwidth="20" marginheight="20">
__HTML
    }
  }
  else {
    gotoLoginPage();
  }
  
  return %user_info;
}


sub gotoLoginPage {
  my ($dbh, $site_dns);
  
  $dbh = dbconnect($COOKIE_MSG);
  if ($dbh) {
    $site_dns = getSiteDNS($dbh, 'D');   
    print header(-type=>'text/html', -charset=>'utf-8');
    alert("The session has expired, please login again.");
    dbclose($dbh);
    redirectTo("$site_dns/cgi-pl/index.pl");      
  }
  else {
    #-- The last resort --#
    print header(-type=>'text/html', -charset=>'utf-8');
    redirectTo("/cgi-pl/index.pl");
  }  
}


sub printPageHeader {
  my ($heading) = @_;
  my ($company_name);
  
  $company_name = getDecoyCompanyName();
  
  print <<__HTML;
  <font class=heading><b>$heading</b></font><br>
  <font class=company>$company_name</font>
  <hr>
__HTML
}


sub printPageFooter {
  my ($copyright);
  
  $copyright = getDecoySiteCopyRight();
 
  print <<__HTML;
 	<p>
  <hr>
  <table cellspacing=0 cellpadding=0 id=footertable width=100% class=table>
	<tr>
    <td><font class=footer>$copyright</font></TD>
  </tr>
  </table>
__HTML
}


sub createSessionRecord {
  my ($dbx, $user_id) = @_;
  my ($ok, $msg, $sql, $sth, $sess_code, $secure_key, $http_user_agent, $valid_until, $ip_address);

  $ok = 1;
  $msg = '';
  
  if ($dbx) {
    $sess_code = _generateSessionCode($dbx, 'A', 64);
    $secure_key = _generateRandomStr('A', 16);           # Reserved to be used later.
    $http_user_agent = $ENV{'HTTP_USER_AGENT'};
    $valid_until = setSessionValidTime();                
    $ip_address = $ENV{'REMOTE_ADDR'};  
        
    $sql = <<__SQL;
    INSERT INTO web_session
    (sess_code, user_id, sess_until, ip_address, http_user_agent, secure_key, status)
    VALUES
    (?, ?, ?, ?, ?, ?, 'A')
__SQL

    $sth = $dbx->prepare($sql);
    if (!$sth->execute($sess_code, $user_id, $valid_until, $ip_address, $http_user_agent, $secure_key)) {
      $msg = $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
    
    if ($ok) {
      #-- Delete all other active session record(s) of this user except the newest created one. i.e. Just one live session per user --#
      #-- is allowed. Note: Login process is considered success, even this process is failure.                                      --# 
      $sql = <<__SQL;
      DELETE FROM web_session
        WHERE user_id = ?
          AND sess_code <> ?
          AND status = 'A'
__SQL

      $sth = $dbx->prepare($sql);
      $sth->execute($user_id, $sess_code);
      $sth->finish;
    }
        
    if ($ok) {
      #-- Reset 'inform_new_msg' flag = 1. Note: Login process is considered success, even this process is failure. --#
      $sql = <<__SQL;
      UPDATE user_list 
        SET inform_new_msg = 1
        WHERE user_id = ?
__SQL
      $sth = $dbx->prepare($sql);
      $sth->execute($user_id);
      $sth->finish;
    }
  }
  else {
    $msg = "Invalid database connection";
    $ok = 0;
  }
  
  return ($ok, $msg, $sess_code);
}


sub _generateSessionCode {
  my ($dbx, $option, $max_len) = @_;
  my ($sql, $sth, $stop_run, $cnt, $rec_cnt, $sess_code);
  
  $max_len += 0;
  $max_len = ($max_len < 64)? 64 : $max_len; 
  $max_len = ($max_len > 128)? 128 : $max_len; 
  
  if ($dbx) {
    $stop_run = $cnt = 0;
    while (!$stop_run) {
      $sess_code = _generateRandomStr($option, $max_len);
      
      $sql = <<__SQL;
      SELECT COUNT(*) AS rec_cnt
        FROM web_session
        WHERE sess_code = ?
__SQL

      $sth = $dbx->prepare($sql);
      if ($sth->execute($sess_code)) {
        ($rec_cnt) = $sth->fetchrow_array();
        $stop_run = ($rec_cnt == 0)? 1 : 0;
      }
      $sth->finish;
      
      if (!$stop_run) {
        $cnt++;
        if ($cnt > 20) {
          #-- It is the last resort --#
          $sess_code = _generateRandomStr($option, 72);
          $stop_run = 1;
        }
      }      
    }
  }
  else {
    #-- Emergency measure --#
    $sess_code = _generateRandomStr('A', 72);
  }

  return $sess_code;  
}


sub sessionExist {
  my ($dbx, $user_id, $sess_code) = @_;
  my ($sql, $sth, $cnt, $result);
  
  if ($dbx) {
    $sql = <<__SQL;
    SELECT COUNT(*) AS cnt
      FROM web_session
        WHERE user_id = ?
          AND sess_code = ?
          AND status = 'A'
__SQL

    $sth = $dbx->prepare($sql);
    if ($sth->execute($user_id, $sess_code)) {
      ($cnt) = $sth->fetchrow_array();
      $result = ($cnt > 0)? 1 : 0;
    }
    else {
      $result = 0;
    }
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub getDecoyCompanyName {
  my ($dbx, $result);

  $dbx = dbconnect($COOKIE_MSG);
    
  if ($dbx) {
    $result = getSysSettingValue($dbx, 'decoy_company_name');
    if (allTrim($result) eq '') {
      $result = $COMP_NAME;
    }    
  }
  else {
    $result = $COMP_NAME;
  }
  
  dbclose($dbx);
  
  return $result;
}


sub getDecoySiteCopyRight {
  my ($company_name, $year, $result);
  
  $company_name = getDecoyCompanyName();  
  ($year) = (localtime())[5];
  $year += 1900;
  
  $result = "Copyright &copy; 2000-$year $company_name";
  
  return $result;
}


sub informSystemAdmin {
  my ($dbh, $subject, $mail_content) = @_;
  my ($ok, $msg, $sql, $sth, $from_mail, $from_user, $from_pass, $smtp_server, $port, $cracked_user, @data, @admins);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  SELECT user_name, user_alias, email
    FROM user_list
    WHERE user_role = 2
      AND status = 'A' 
__SQL

  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (@data = $sth->fetchrow_array()) {
    push @admins, {'name' => $data[0], 'alias' => $data[1], 'email' => $data[2]};
  }
  $sth->finish;
  
  if (scalar(@admins) > 0) {
    ($from_mail, $from_user, $from_pass, $smtp_server, $port) = getSysEmailSender($dbh);                      # Defined on sm_webenv.pl
  
    foreach my $rec (@admins) {
      my $this_admin = (allTrim($rec->{'alias'}) ne '')? $rec->{'alias'} : $rec->{'name'};
      my $this_email = $rec->{'email'}; 

      #-- Note: '$this_admin' is UTF-8 encoded, so that it must be decoded before pass to 'sendOutGmail'. --#
      $this_admin = decode('utf8', $this_admin);
      
      my $body = "Hi $this_admin, \n\n" .
                 "$mail_content \n\n" .
                 "Best Regards, \n" .
                 "Information Team.\n";
      
      my ($this_ok, $this_msg) = sendOutGmail($from_mail, $this_email, $from_user, $from_pass, $smtp_server, $port, $subject, $body);     # Defined on sm_webenv.pl
      if (!$this_ok) {
        $msg .= "Unable to inform system administrator $this_admin \n";
        $ok = 0;
      }      
    }     
  }
  
  if (!$ok) {
    $msg .= "Error is found as inform system administrator(s) for event '$subject': \n\n" . $msg;
  }
  
  return ($ok, $msg);
}


sub utf8_substring {
  my ($str, $start, $str_len) = @_;   # Note: $str_len means the no. of characters of the result, not the value of length($result).
  my ($char, $char_pt, $char_cnt, $result, @chars);
    
  if (length($str) == 0 || $start < 0 || $str_len <= 0) {
    return '';
  }
  
  $char = $result = '';
  $char_cnt = $char_pt = 0;
  
  @chars = $str =~ /$utf_8/gosx;      # $str must be in ASCII or UTF-8 format.
  
  foreach $char (@chars) {
    if ($char_pt >= $start && $char_cnt <= $str_len) {
      $result .= $char;
      $char_cnt++;
    }        
    $char_pt++;    
    last if ($char_cnt >= $str_len);
  }
  
  return $result;
}


sub utf8_length {
  my ($str) = @_;
  my ($result, @chars);
	
  @chars = $str =~ /$utf_8/gosx;      # $str must be in ASCII or UTF-8 format.
  $result = scalar(@chars);

  return $result;
}


sub getTelegramBotProfile {
  my ($dbh) = @_;
  my ($sql, $sth, @data, %result);
  
  $sql = <<__SQL;
  SELECT bot_name, bot_username, http_api_token
    FROM tg_bot_profile
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    @data = $sth->fetchrow_array();
    %result = ('bot_name' => $data[0], 'bot_username' => $data[1], 'http_api_token' => $data[2]);
  }
  
  return %result;
}


sub fileUpload {
  my ($ul_file) = @_;
  my ($ok, $msg, $filename, $dirs, $suffix, $temp_filename, $final_filename, $stop_run, $idx, $len, $r_len);
  
  $ok = 1;
  $msg = '';
  
  $temp_filename = tmpFileName($ul_file);           # It is a function of CGI. Note: function tmpFileName will return the file name of a temporary file which is used to store the content of the upload file. 
  ($filename, $dirs, $suffix) = fileNameParser($ul_file);
  #-- 2019-02-04 AY: Extend short file name to avoid hackers guessing it easily --# 
  $len = utf8_length($filename);
  $r_len = _randomLength();
  if ($len < $r_len) {
    my $len_diff = $r_len - $len;
    $filename = $filename . _generateRandomStr('A', $len_diff);
  }  
  $final_filename = "$ITN_FILE_PATH/$filename$suffix";
  
  if (-f $final_filename) {
    $idx = 1;
    $stop_run = 0;
    while (!$stop_run) {
      my $ver_idx = sprintf("%03d", $idx); 
      $final_filename = "$ITN_FILE_PATH/$filename-$ver_idx$suffix";
      
      if (!(-f $final_filename)) {
        $stop_run = 1;
      }
      else {
        $idx++;
        
        if ($idx > 999) {
          #-- Final resort --#
          $filename = _generateRandomStr('A', 16);
          $final_filename = "$ITN_FILE_PATH/$filename$suffix";
          $stop_run = 1;
        }
      }
    }
  }
      
  if (!copy("$temp_filename", "$final_filename")) {
    $msg = "Unable to upload file. Error: $!";
    $ok = 0;
  }
  
  return ($ok, $msg, $final_filename);  
}


sub fileNameParser {
  my ($file) = @_;
  my ($filename, $dirs, $suffix);
  
  ($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*/);
  
  return ($filename, $dirs, $suffix);
}


sub findFileType {
  my ($dbh, $file_ext) = @_;
  my ($sql, $sth, $result);
  
  $file_ext =~ s/\.//g;         # Remove '.' if it exists.
  
  $sql = <<__SQL;
  SELECT file_type
    FROM file_type
    WHERE file_ext = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($file_ext)) {
    ($result) = $sth->fetchrow_array();
  }
  
  return allTrim($result);
}


sub createThumbnail {
  my ($photo, $tn_path) = @_;
  my ($ok, $msg, $image, $error, $filename, $dirs, $suffix, $tn_filename);
  
  $ok = 1;
  $msg = '';
  
  #-- Create an Image::Magick instance --#
  $image = new Image::Magick;
  #-- Load up the image file --#
  $error = $image->Read($photo);
  if ($error) {
    $msg = "Unable to read given image file $photo. Error: $error";
    $ok = 0;
  }
  
  if ($ok) {
    ($filename, $dirs, $suffix) = fileNameParser($photo);
    $tn_filename = "$tn_path/$filename.jpg";
    if (-f $tn_filename) {
      unlink $tn_filename;
    }
    
    my ($th, $tw) = $image->Get('height', 'width');
    if ($th > 10 && $tw > 10) {
      $th = sprintf("%d", $th/5);
      $tw = sprintf("%d", $tw/5);
    }
    
    $error = $image->Thumbnail(width => $tw, height => $th);
    if ($error) {
      $msg = "Unable to prepare thumbnail. Error: $error";
      $ok = 0;
    }
    
    if ($ok) {
      $error = $image->Write("jpg:$tn_filename");
      if ($error) {
        $msg = "Unable to create thumbnail file. Error: $error";
        $ok = 0;
      }      
    }
  }
  
  return ($ok, $msg, $tn_filename);
}


sub getSysSettingValue {
  my ($dbh, $sys_key) = @_;
  my ($sql, $sth, $result);
  
  $result = '';
  
  $sql = <<__SQL;
  SELECT sys_value
    FROM sys_settings
    WHERE sys_key = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($sys_key)) {
    ($result) = $sth->fetchrow_array();
  }
  $sth->finish;
  
  return $result;
}


sub convertAudioFile {
  my ($audio_converter, $input_file) = @_;
  my ($ok, $msg, $f_name, $dirs, $suffix, $output_file, $command);
  
  $ok = 1;
  $msg = '';
  
  if (-f $input_file) {
    ($f_name, $dirs, $suffix) = fileNameParser($input_file);
    $output_file = "$dirs$f_name.ogg";
  
    #-- Note: To define a audio converter setting, the generic format is as follows:                                                 --#
    #--       audio_converter_with_full_path <optional options> '{input_file}' <optional options> '{output_file}' <optional options> --#
    #--       For example: /usr/bin/ffmpeg -i '{input_file}' '{output_file}'                                                         --#   
    $audio_converter =~ s/{input_file}/$input_file/gi;
    $audio_converter =~ s/{output_file}/$output_file/gi;
  
    $command = $audio_converter;     
    system($command);
    if (-f "$output_file") {
      #-- If the audio file has been converted successfully, delete the original audio file. --#
      unlink "$input_file";        
    }
    else {
      $msg = "Unable to create HTML5 compatible audio file for $input_file";
      $ok = 0;
      #-- If file conversion is failure, just return the original input file. User may determine what to do next. --#
      $output_file = $input_file;      
    }    
  }
  else {
    $output_file = $input_file;     # Follow error handling convention.
    $msg = "Input file $input_file does't exist";
    $ok = 0;
  }
  
  return ($ok, $msg, $output_file);
}


sub telegramBotDefined() {
  my ($dbh) = @_;
  my ($sql, $sth, $result);
  
  if (!$dbh) {
    $dbh = dbconnect($COOKIE_MSG);
  }
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT bot_username, http_api_token
      FROM tg_bot_profile
__SQL
    
    $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
      my @data = $sth->fetchrow_array();
      if (allTrim($data[0]) ne '' && allTrim($data[1]) ne '') {
        $result = 1;
      }
      else {
        $result = 0; 
      }
    }
    else {
      $result = 0;
    }
    $sth->finish;
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub getCurrentDateTime {
  my ($dbh, $params_ref) = @_;
  my ($sql, $sth, $result, %params);
  
  $result = '';
  
  %params = ($params_ref ne undef)? %$params_ref : ();
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT CURRENT_TIMESTAMP() AS cdt   
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
      ($result) = $sth->fetchrow_array();
      
      if ($params{'no_sec'} == 1) {
        my @dt_parts = split(' ', $result);
        my $time = allTrim($dt_parts[1]);
        my @time_parts = split(':', $time);
        $time = $time_parts[0] . ':' . $time_parts[1];
        $result = allTrim($dt_parts[0]) . " $time";
      }
    }
    $sth->finish;
  }
  
  if ($result eq '') {
    #-- Last resort --#
	  my ($year, $month, $day, $hour, $min, $sec) = (localtime())[5, 4, 3, 2, 1, 0];
	  $month++;
	  $year += 1900;
    $result = $year . '-' . sprintf("%02d", $month) . '-' . sprintf("%02d", $day) . (($params{'no_sec'} == 1)? ' $hour:$min' : ' $hour:$min:$sec');
  }
  
  return $result;
}


sub getCurrentTime {
  my ($dbh, , $params_ref) = @_;
  my ($sql, $sth, $result, %params);
  
  $result = '';
  
  %params = ($params_ref ne undef)? %$params_ref : ();  
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT CURRENT_TIME() AS ct   
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
      ($result) = $sth->fetchrow_array();
      
      if ($params{'no_sec'} == 1) {
        my @time_parts = split(':', $result);
        $result = $time_parts[0] . ':' . $time_parts[1];
      }
    }
    $sth->finish;
  }
  
  if ($result eq '') {
    #-- Last resort --#
	  my ($hour, $min, $sec) = (localtime())[2, 1, 0];
    $result = sprintf("%02d", $hour) . ':' . sprintf("%02d", $min) . (($params{'no_sec'} == 1)? '' : ':' . sprintf("%02d", $sec));
  }
  
  return $result;  
}


sub _randomLength {
  my ($low_limit, $high_limit, $stop_run, $cnt, $result);
  
  $low_limit = 14;
  $high_limit = 20;
    
  $stop_run = $cnt = $result = 0;
  while (!$stop_run) {
    my $this_value = sprintf("%d", rand($high_limit + 1));
    if ($this_value >= $low_limit && $this_value <= $high_limit) {
      $result = $this_value;
      $stop_run = 1;
    }
    else {
      $cnt++;
      if ($cnt > 20) {
        $result = $high_limit;
        $stop_run = 1;
      }
    }
  }

  return $result;
}


1;
