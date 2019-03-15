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
# Program: /www/pdatools/cgi-pl/tools/notes.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-15      AY              A note editor. 
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

my $op = paramAntiXSS('op');                                          # 'A' = Add new notes, 'E' = Modify notes, 'D' = Delete notes, 'R' = Read notes, others = List notes. 
my $oper_mode = paramAntiXSS('oper_mode');                            # 'S' = Save.
my $list_filter = paramAntiXSS('list_filter');                        # Key words filter on notes title for notes searching.
my $notes_id = paramAntiXSS('notes_id') + 0;
my $notes_title = paramAntiXSS('notes_title');
my $notes_content = paramAntiXSS('notes_content');

my $dbh = dbconnect($COOKIE_PDA);

my %user_info = printHead($COOKIE_PDA);                               # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @notes_list;
my %notes_dtl;
my $ok = 1;
my $msg = '';

printJavascriptSection();

if ($op eq 'A') {
  if ($oper_mode eq 'S') {
    ($ok, $msg, $notes_id) = addNewNotes($dbh, $user_id, $notes_title, $notes_content);
    if ($ok) {
      redirectTo("/cgi-pl/tools/notes.pl?op=R&notes_id=$notes_id");
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    printNewNotesForm();
  }
}
elsif ($op eq 'E') {
  if ($oper_mode eq 'S') {
    ($ok, $msg) = modifyNotes($dbh, $notes_id, $notes_title, $notes_content);
    if ($ok) {
      redirectTo("/cgi-pl/tools/notes.pl?op=R&notes_id=$notes_id");
    }
    else {
      alert($msg);
      back();
    }
  }
  else {
    %notes_dtl = getNotesDetails($dbh, $notes_id);
    printEditNotesForm($notes_id, \%notes_dtl);
  }
}
elsif ($op eq 'D') {
  ($ok, $msg) = deleteNotes($dbh, $notes_id);
  if (!$ok) {
    alert($msg);
  }
  redirectTo("/cgi-pl/tools/notes.pl");
}
elsif ($op eq 'R') {
  %notes_dtl = getNotesDetails($dbh, $notes_id);
  printNotesDetails($notes_id, \%notes_dtl);
}
else {
  @notes_list = getNotesList($dbh, $user_id, $list_filter);
  printNotesList(\@notes_list);
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
    function goSearch() {
      var filter = \$('#list_filter').val();
      \$('#frm_notes').submit();
    }
    
    function readNotes(notes_id) {
      \$('#op').val("R");
      \$('#notes_id').val(notes_id);
      \$('#frm_notes').submit();
    }
    
    function editNotes(notes_id) {
      \$('#op').val("E");
      \$('#notes_id').val(notes_id);
      \$('#frm_notes').submit();      
    }
    
    function deleteNotes(notes_id) {
      if (confirm("Delete this notes?")) {
        \$('#op').val("D");
        \$('#notes_id').val(notes_id);
        \$('#frm_notes').submit();        
      }
    }
    
    function discard() {
      var contents = allTrim(\$('#notes_content').val());

      if (contents != "") {
        if (confirm("Discard your new notes?")) {
          window.location.href = "/cgi-pl/tools/notes.pl"; 
        }
      }
      else {
        window.location.href = "/cgi-pl/tools/notes.pl";
      }
    }
    
    function saveNotes() {
      if (dataSetValid()) {
        \$('#oper_mode').val("S");
        \$('#frm_notes').submit();
      }
    }
    
    function dataSetValid() {
      var title = allTrim(\$('#notes_title').val());
      var contents = allTrim(\$('#notes_content').val());
      
      if (title == "") {
        alert("Please input notes title before saving");
        \$('#notes_title').focus();
        return false;
      }
      
      if (title == "") {
        alert("Please input your notes before saving");
        \$('#notes_content').focus();
        return false;
      }
      
      return true;
    }
    
    function addNewNotes() {
      \$('#op').val("A");
      \$('#frm_notes').submit();
    }
  </script>
__JS
}


sub addNewNotes {
  my ($dbh, $user_id, $notes_title, $notes_content) = @_;
  my ($ok, $msg, $notes_id, $sql, $sth);

  $ok = 1;
  $msg = '';
  $notes_id = 0;
  
  $sql = <<__SQL;
  INSERT INTO notes
  (user_id, notes_title, notes_content, create_date)
  VALUES
  (?, ?, ?, CURRENT_TIMESTAMP())
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($user_id, $notes_title, $notes_content)) {
    $msg = "Unable to add new notes. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
    if ($sth->execute()) {
      ($notes_id) = $sth->fetchrow_array();
      if ($notes_id <= 0) {
        $msg = "Unable to retrieve ID of the newly added notes by unknown reason.";
        $ok = 0;
      }
    }
    else {
      $msg = "Unable to retrieve ID of the newly added notes. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg, $notes_id);
}


sub printNewNotesForm {
  my ($html);
  
  #-- Note: For jQuery mobile, it will use Ajax method for form data submission by default, so if you want to handle form data submission --#
  #--       without Ajax, you need to put data-ajax="false" on the form object.                                                           --#
  $html = <<__HTML;
  <form id="frm_notes" name="frm_notes" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
    
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:discard()" data-icon="back" data-ajax="false">Discard</a>
      <h1>Add Notes</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <label for="notes_title"><b>Title:</b></label>
      <input type=text id="notes_title" name="notes_title" value="$notes_title" maxlength=256>
      <br>
      <label for="notes_content"><b>Notes:</b></label>
      <textarea id="notes_content" name="notes_content">$notes_content</textarea>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center>
            <input type=button id="save" name="save" value="Save Notes" data-icon="plus" onClick="saveNotes()">
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


sub modifyNotes {
  my ($dbh, $notes_id, $notes_title, $notes_content) = @_;
  my ($ok, $msg, $sql, $sth);

  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE notes
    SET notes_title = ?,
        notes_content = ?,
        update_date = CURRENT_TIMESTAMP()
    WHERE notes_id = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($notes_title, $notes_content, $notes_id)) {
    $msg = "Unable to update this notes. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getNotesDetails {
  my ($dbh, $notes_id) = @_;
  my ($sql, $sth, %result);
  
  $sql = <<__SQL;
  SELECT notes_title, notes_content
    FROM notes
    WHERE notes_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($notes_id)) {
    my @data = $sth->fetchrow_array();
    %result = ('title' => $data[0], 'content' => $data[1]);    
  }
  $sth->finish;
  
  return %result;
}


sub printEditNotesForm {
  my ($notes_id, $notes_dtl_ref) = @_;
  my ($html, %notes_dtl);
  
  %notes_dtl = %$notes_dtl_ref;
  
  $html = <<__HTML;
  <form id="frm_notes" name="frm_notes" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="notes_id" name="notes_id" value="$notes_id">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/tools/notes.pl?op=R&notes_id=$notes_id" data-icon="back" class="ui-btn-left">Back</a>
      <h1>Edit Notes</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <label for="notes_title"><b>Title:</b></label>
      <input type=text id="notes_title" name="notes_title" value="$notes_dtl{'title'}" maxlength=256>
      <br>
      <label for="notes_content"><b>Notes:</b></label>
      <textarea id="notes_content" name="notes_content">$notes_dtl{'content'}</textarea>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center>
            <input type=button id="save" name="save" value="Save Notes" data-icon="plus" onClick="saveNotes()">
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


sub deleteNotes {
  my ($dbh, $notes_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM notes
    WHERE notes_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($notes_id)) {
    $msg = "Unable to delete this notes. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub printNotesDetails {
  my ($notes_id, $notes_dtl_ref) = @_;
  my ($html, %notes_dtl);
  
  %notes_dtl = %$notes_dtl_ref;  
  $notes_dtl{'content'} =~ s/\n/<br>/g;           # Carriage return
  $notes_dtl{'content'} =~ s/\t/&#9;/g;           # Tab
  $notes_dtl{'content'} =~ s/ /&nbsp;/g;          # Space
  
  $html = <<__HTML;
  <form id="frm_notes" name="frm_notes" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="notes_id" name="notes_id" value="$notes_id">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/tools/notes.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Read Notes</h1>
    </div>
    
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellspacing=1>
      <thead></thead>
      <tbody>
        <tr>
          <td width=50% align=center>
            <input type=button id="edit" name="edit" data-icon="gear" value="Edit" onClick="editNotes($notes_id)">          
          </td>
          <td width=50% align=center>
            <input type=button id="edit" name="edit" data-icon="delete" value="Delete" onClick="deleteNotes($notes_id)">
          </td>
        </tr>
      </tbody>
      </table>
      <br>
      
      <table width=100% cellspacing=1 cellspacing=1 style="table-layout:fixed;">
      <thead></thead>
      <tbody>
        <tr style="background-color: lightblue">
          <td style="word-wrap:break-word;"><b>$notes_dtl{'title'}</b></td> 
        </tr>
        <tr style="background-color: lightyellow">
          <td style="word-wrap:break-word;">$notes_dtl{'content'}</td> 
        </tr>
        <tr style="background-color: lightblue">
          <td>&nbsp;</td> 
        </tr>        
      </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub getNotesList {
  my ($dbh, $user_id, $list_filter) = @_;
  my ($sql, $sth, $filter, @keywords, @sqlcomm, @result);
  
  if (allTrim($list_filter) ne '') {
    @keywords = split(' ', $list_filter);
    foreach my $keyword (@keywords) {
      push @sqlcomm, "notes_title LIKE '%$keyword%'";
    }
    $filter = "AND (" . join(' OR ', @sqlcomm) . ")";
  }
  else {
    $filter = '';
  }
  
  $sql = <<__SQL;
  SELECT notes_id, notes_title
    FROM notes
    WHERE user_id = ?
    $filter
    ORDER BY notes_title
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user_id)) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'notes_id' => $data[0], 'notes_title' => $data[1]};
    }
  }
  
  return @result;
}


sub printNotesList {
  my ($notes_list_ref) = @_;
  my ($html, @notes_list);
  
  @notes_list = @$notes_list_ref;
  
  $html = <<__HTML;
  <form id="frm_notes" name="frm_notes" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="oper_mode" name="oper_mode" value="">  
  <input type=hidden id="notes_id" name="notes_id" value="0">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/tools/select_tools.pl" data-icon="home" class="ui-btn-left" data-ajax="false">Home</a>
      <h1>Notes</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead></thead>
      <tbody>
        <tr>
          <td width=80%>
            <input type=text id="list_filter" name="list_filter" value="$list_filter">
          </td>
          <td align=center valign=center>
            <input type=button data-icon="search" data-iconpos="notext" id="search" name="search" onClick="goSearch()">
          </td>
        </tr>
      </tbody>
      </table>
      
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed">
      <thead>
        <tr style="background-color:lightblue">
          <td width=75% align=center><b>Title</b></td>
          <td align=center><b>Delete</b></td>
        </tr>
      </thead>
      <tbody>
__HTML

  foreach my $rec (@notes_list) {
    my $this_notes_id = $rec->{'notes_id'};
    my $this_notes_title = $rec->{'notes_title'};
    
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td style="word-wrap:break-word"><a href="javascript:readNotes($this_notes_id)">$this_notes_title</a></td>
          <td align=center valign=center><input type=button id="kill_notes" name="kill_notes" data-icon="delete" data-iconpos="notext" onClick="deleteNotes($this_notes_id)">
        </tr>
__HTML
  }
  
  if (scalar(@notes_list) == 0) {
    $html .= <<__HTML;
        <tr style="background-color:lightgray">
          <td colspan=2>No Record</td>
        </tr>
__HTML
  }

  $html .= <<__HTML;
        <tr style="background-color:lightblue">
          <td colspan=2 align=center>&nbsp;</td>
        </tr>        
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=1 cellpadding=1>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center>
            <input type=button id="add_notes" name="add_notes" value="Add New Notes" data-icon="plus" onClick="addNewNotes()">
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
