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
# Program: /www/pdatools/cgi-pl/admin/feature_setup.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-11-27      AY              Maintain features used on the decoy site.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_PDA;                                           # Defined on sm_webenv.pl 
our $COOKIE_MSG;                                           # Defined on sm_webenv.pl
our $PDA_BG_COLOR;                                         # Defined on sm_webenv.pl
our $PDA_IMG_PATH;                                         # Defined on sm_webenv.pl
our $PDA_TOOLS_PATH;                                       # Defined on sm_webenv.pl

my $op = paramAntiXSS('op');                               # A = Add, E = Edit, D = Delete, G = Assign.
my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $feature_id = paramAntiXSS('feature_id');               # Unique ID of feature.
my $feature_url = paramAntiXSS('feature_url');             # Feature calling URL.
my $feature_icon = paramAntiXSS('feature_icon');           # Feature icon file name.
my $assign_to_list = paramAntiXSS('assign_to_list') + 0;   # 0 = No, 1 = Yes, assign this feature to list.
my $list_order = paramAntiXSS('list_order') + 0;           # Listing order number. It must be an integer.   

my $dbh = dbconnect($COOKIE_PDA);
my $dbx = dbconnect($COOKIE_MSG);

my %user_info = printHead($COOKIE_PDA);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @feature_list = ();                                     # List of defined features.
my %feature_dtl = ($op eq 'E' && $oper_mode ne 'S')? getFeatureInfo($dbh, $feature_id) : ();

printJavascriptSection();

if (isHeSysAdmin($dbx, $user_id)) {
  if ($op eq 'A') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = addNewFeature($dbh, $feature_url, $feature_icon, $assign_to_list, $list_order);
      if ($ok) {
        redirectTo("/cgi-pl/admin/feature_setup.pl");
      }
      else {
        alert($msg);
        back();
      }
    }
    else {
      printAddFeatureForm();
    }
  }
  elsif ($op eq 'E') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = updateFeature($dbh, $feature_id, $feature_url, $feature_icon, $assign_to_list, $list_order);
      if ($ok) {
        redirectTo("/cgi-pl/admin/feature_setup.pl");
      }
      else {
        alert($msg);
        back();        
      }
    }
    else {
      printEditFeatureForm(\%feature_dtl);
    }
  }
  elsif ($op eq 'D') {
    if ($feature_id > 0) {
      my ($ok, $msg) = deleteFeature($dbh, $feature_id);
      if (!$ok) {
        alert($msg);
      }      
    }
    else {
      alert("Invalid feature record id is given");
    }
    
    redirectTo("/cgi-pl/admin/feature_setup.pl");
  }
  else {
    @feature_list = getFeatureFromStore($dbh);
    printFeatureList(\@feature_list);
  }
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. --#
  redirectTo("/cgi-pl/auth/logout.pl");  
}

dbclose($dbh);
dbclose($dbx);
#-- End Main Section --#


sub printJavascriptSection {
  my ($assigned);
  
  $assigned = 0;
  if ($oper_mode ne 'S') {
    if ($op eq 'A') {
      $assigned = $assign_to_list; 
    }
    elsif ($op eq 'E') {
      $assigned = ($feature_dtl{'order'} > 0)? 1 : 0;
    }
  }
  
  print <<__JS;
	<link rel="stylesheet" href="/js/jquery.mobile-1.4.5.min.css">
	<link rel="shortcut icon" href="/favicon.ico">
	<script src="/js/jquery.min.js"></script>
  <script src="/js/jquery.mobile-1.4.5.min.js"></script>
  <script src="/js/common_lib.js"></script>

  <script>
    \$(document).on("pagecreate", function() {
      var assign_to_list = $assigned;
      
      if (assign_to_list > 0) {
        \$("#input_order").show();  
      }
      else {
        \$("#input_order").hide();
      }
    });
    
    //*-- Define event handler of checkbox 'assign_to_list' --*//
    \$(function() {
      \$("#assign_to_list").on('change', function() {
        if (this.checked) {
          \$("#input_order").show();
        }
        else {
          \$("#input_order").hide();
        }
      })      
    });    
    
    function addFeature() {
      \$('#op').val('A');
      \$('#frm_feature').submit();
    }
    
    function goBack() {
      \$('#op').val('');
      \$('#frm_feature').submit();
    }
    
    function saveFeature() {
      if (dataSetValid()) {
        \$('#oper_mode').val('S');
        \$('#frm_feature').submit();
      }
    }
    
    function dataSetValid() {
      var this_icon = allTrim(\$('#feature_icon').val());
      var this_url = allTrim(\$('#feature_url').val());
      
      if (this_icon == "") {
        alert("Please select an icon for this feature before saving");
        \$('#feature_icon').focus();
        return false;
      }
      
      if (this_url == "") {
        alert("Pleas select a program script of this feature before saving");
        \$('#feature_url').focus();
        return false;
      }
      
      normalizeAssignToListData();
            
      return true;
    }
    
    function normalizeAssignToListData() {
      var is_checked = \$('#assign_to_list').is(':checked');
      if (is_checked == false) {
        \$('#assign_to_list').val(0);
        \$('#list_order').val(0);
      }
      else {
        \$('#assign_to_list').val(1);
        var this_list_order = parseInt(\$('#list_order').val(), 10);
        if (isNaN(this_list_order) || (this_list_order < 1 || this_list_order > 99)) {
          \$('#list_order').val(99);
        }
      }      
    }
  
    function editFeature(feature_id) {
      \$('#feature_id').val(feature_id);
      \$('#op').val('E');
      \$('#frm_feature').submit();
    }
    
    function updateFeature() {
      normalizeAssignToListData();
      \$('#oper_mode').val('S');
      \$('#frm_feature').submit();
    }

    function deleteFeature(feature_id) {
      if (confirm("Are you sure to delete this feature?")) {
        if (confirm("Last chance, really want to delete this feature?")) {
          \$('#feature_id').val(feature_id);
          \$('#op').val('D');
          \$('#frm_feature').submit();          
        }
      }
    }
  </script>
__JS
}


sub isHeSysAdmin {
  my ($dbx, $user_id) = @_;
  my ($role, $result);
  
  $role = getUserRole($dbx, $user_id);               # Defined on sm_user.pl
  $result = ($role == 2)? 1 : 0;
  
  return $result;  
}


sub addNewFeature {
  my ($dbh, $feature_url, $feature_icon, $assign_to_list, $list_order) = @_;
  my ($ok, $msg, $feature_id, $icon_url, $program_url);
  
  $ok = 1;
  $msg = '';
  
  ($ok, $msg, $icon_url) = processUploadFile('ICON', $PDA_IMG_PATH, $feature_icon);
  
  if ($ok) {
    ($ok, $msg, $program_url) = processUploadFile('PROGRAM', $PDA_TOOLS_PATH, $feature_url);
  }
  
  if ($ok) {
    if (startTransaction($dbh)) {
      ($ok, $msg, $feature_id) = createFeature($dbh, $icon_url, $program_url);
      
      if ($ok && $assign_to_list) {
        ($ok, $msg) = assignFeatureToList($dbh, $feature_id, $list_order);
      }
      
      if ($ok) {
        commitTransaction($dbh);
      }
      else {
        rollbackTransaction($dbh); 
      }
    }
    else {
      $msg = "Unable to start SQL transaction session, operation is aborted.";
      $ok = 0;
    }
  }
  
  return ($ok, $msg);
}


sub processUploadFile {
  my ($option, $store_path, $upload_file, $old_file) = @_;
  my ($ok, $msg, $url, $mode, $filename, $dirs, $suffix, $temp_filename, $final_filename);
  
  $ok = 1;
  $msg = '';
  
  if ($option eq 'ICON') {
    $url = '/images';
    $mode = 0666;        # readable and writable
  }
  elsif ($option eq 'PROGRAM') {
    $url = '/cgi-pl/tools';
    $mode = 0777;        # readable, writable and executable
  }
  else {
    $msg = "Invalid option '$option' for uploaded file processing is given, operation is aborted now.";
    $ok = 0;
  }
  
  if ($ok) {
    $old_file = allTrim($old_file);
    if ($old_file ne '') {
      if (-f $old_file) {
        unlink $old_file;
      }
    }
        
    $temp_filename = tmpFileName($upload_file);           # It is a function of CGI. Note: function tmpFileName will return the file name of a temporary file which is used to store the content of the upload file. 
    ($filename, $dirs, $suffix) = fileNameParser($upload_file);
    $final_filename = "$store_path/$filename$suffix";
    
    if (-f $final_filename) {
      $msg = "$filename$suffix has already existed, operation is aborted now.";
      $ok = 0;
    }
    else {
      if (!copy("$temp_filename", "$final_filename")) {
        $msg = "Unable to upload file $filename$suffix ($temp_filename --> $final_filename). Error: $!";
        $ok = 0;
        $url = '';
      }
      else {
        chmod $mode, $final_filename;
        $url .= "/$filename$suffix";  
      }
    }
  }
  
  return ($ok, $msg, $url);  
}


sub createFeature {
  my ($dbh, $icon_url, $program_url) = @_;
  my ($ok, $msg, $feature_id, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO feature_store
  (feature_url, feature_icon)
  VALUES
  (?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($program_url, $icon_url)) {
    $msg = "Unable to add new feature. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    $sth = $dbh->prepare("SELECT LAST_INSERT_ID()");
    if ($sth->execute()) {
      ($feature_id) = $sth->fetchrow_array();
      if ($feature_id <= 0) {
        $msg = "Unable to retrieve the feature id by unknown reason";
        $ok = 0;
      }      
    }
    else {
      $msg = "Unable to retrieve the feature id. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg, $feature_id);
}


sub assignFeatureToList {
  my ($dbh, $feature_id, $list_order) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $feature_id += 0;
  $list_order = sprintf("%d", $list_order);
  
  #-- Step 1: Clear all records with given feature id --#
  $sql = <<__SQL;
  DELETE FROM feature_list
    WHERE feature_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($feature_id)) {
    $msg = "Unable to clear old record on feature list. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Step 2: Assign feature to list --#
    $sql = <<__SQL;
    INSERT INTO feature_list
    (feature_id, list_order)
    VALUES
    (?, ?)
__SQL
 
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($feature_id, $list_order)) {
      $msg = "Unable to assign feature to list. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}


sub updateFeature {
  my ($dbh, $feature_id, $new_ul_program, $new_ul_icon, $assign_to_list, $list_order) = @_;
  my ($ok, $msg, $old_icon_file, $old_program_file, $icon_url, $program_url);
  
  $ok = 1;
  $msg = '';
  
  ($old_icon_file, $old_program_file) = getFeatureDetails($dbh, $feature_id);
  
  if (allTrim($new_ul_icon) ne '') {
    ($ok, $msg, $icon_url) = processUploadFile('ICON', $PDA_IMG_PATH, $new_ul_icon, $old_icon_file);
  }
  
  if ($ok && allTrim($new_ul_program) ne '') {
    ($ok, $msg, $program_url) = processUploadFile('PROGRAM', $PDA_TOOLS_PATH, $new_ul_program, $old_program_file);
  }
  
  if ($ok) {
    if (startTransaction($dbh)) {
      ($ok, $msg) = updateFeatureRecord($dbh, $feature_id, $icon_url, $program_url);
      
      if ($ok) {
        if ($assign_to_list) {
          ($ok, $msg) = assignFeatureToList($dbh, $feature_id, $list_order);
        }
        else {
          ($ok, $msg) = removeFeatureFromList($dbh, $feature_id);
        }
      }
      
      if ($ok) {
        commitTransaction($dbh);
      }
      else {
        rollbackTransaction($dbh);
      }
    }
    else {
      $msg = "Unable to start SQL transaction session, process is failure. Note: related files of this feature have been replaced by uploaded files (if any).";
      $ok = 0;
    }
  }
  
  return ($ok, $msg);
}


sub updateFeatureRecord {
  my ($dbh, $feature_id, $icon_url, $program_url) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';

  if ($icon_url ne '') {
    $sql = <<__SQL;
    UPDATE feature_store
      SET feature_icon = ?
      WHERE feature_id = ?
__SQL
    
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($icon_url, $feature_id)) {
      $msg = "Unable to update feature icon. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  if ($ok && $program_url ne '') {
    $sql = <<__SQL;
    UPDATE feature_store
      SET feature_url = ?
      WHERE feature_id = ?
__SQL
    
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($program_url, $feature_id)) {
      $msg = "Unable to update feature program. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}


sub removeFeatureFromList {
  my ($dbh, $feature_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM feature_list
    WHERE feature_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($feature_id)) {
    $msg = "Unable to remove feature from list. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub getFeatureInfo {
  my ($dbh, $feature_id) = @_;
  my ($sql, $sth, %result);
  
  $sql = <<__SQL;
  SELECT a.feature_url, a.feature_icon, b.list_order
    FROM feature_store a LEFT OUTER JOIN feature_list b ON a.feature_id = b.feature_id
    WHERE a.feature_id = ?
__SQL
 
  $sth = $dbh->prepare($sql);
  if ($sth->execute($feature_id)) {
    my @data = $sth->fetchrow_array();
    %result = ('url' => $data[0], 'icon' => $data[1], 'order' => $data[2] + 0);
  }
  $sth->finish;
  
  return %result;
}


sub printEditFeatureForm {
  my ($feature_dtl_ref) = @_;
  my ($html, $checked, $url, $icon, $assign_to_list, $list_order, %feature_dtl);
  
  %feature_dtl = %$feature_dtl_ref;
  $url = extractFileName($feature_dtl{'url'});
  $icon = extractFileName($feature_dtl{'icon'});
  $checked = ($feature_dtl{'order'} > 0)? 'checked' : '';
  $assign_to_list = ($feature_dtl{'order'} > 0)? 1 : 0;
  $list_order = ($feature_dtl{'order'} > 0)? $feature_dtl{'order'} : 1; 
  
  $html = <<__HTML;
  <form id="frm_feature" name="frm_feature" action="" method="post" enctype="multipart/form-data" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="feature_id" name="feature_id" value="$feature_id">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack()" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Add Feature</h1>
    </div>
  
    <div data-role="content">
      <label for="feature_icon"><b>Icon:</b></label>
      <font color="blue">$icon</font> <input type=file id="feature_icon" name="feature_icon">
      <label for="feature_url"><b>Program File:</b></label>
      <font color="blue">$url</font> <input type=file id="feature_url" name="feature_url">
      <label for="assign_to_list"><b>Assign to Feature List:</b></label>
      <input type="checkbox" data-role="flipswitch" id="assign_to_list" name="assign_to_list" value="$assign_to_list" $checked>
      <br>
      <div id="input_order">
        <label for="list_order"><b>Order On List (1-99):</b.</label>
        <input type="number" id="list_order" name="list_order" value="$list_order" min="1" max="99">
      </div>      
      <br>
      <input type=button data-icon="plus" value="Save" onClick="updateFeature()">
    </div>
  </div>  
__HTML
  
  print $html;
}


sub printAddFeatureForm {
  my ($html, $checked);
  
  $checked = ($assign_to_list > 0)? 'checked' : '';
  
  $html = <<__HTML;
  <form id="frm_feature" name="frm_feature" action="" method="post" enctype="multipart/form-data" data-ajax="false">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">  
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack()" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Add Feature</h1>
    </div>
  
    <div data-role="content">
      <label for="feature_icon"><b>Icon:</b></label>
      <input type=file id="feature_icon" name="feature_icon">
      <label for="feature_url"><b>Program File:</b></label>
      <input type=file id="feature_url" name="feature_url">
      <label for="assign_to_list"><b>Assign to Feature List:</b></label>
      <input type="checkbox" data-role="flipswitch" id="assign_to_list" name="assign_to_list" value="$assign_to_list" $checked>
      <br>
      <div id="input_order">
        <label for="list_order"><b>Order On List (1-99):</b></label>
        <input type="number" id="list_order" name="list_order" value="1" min="1" max="99">
      </div>      
      <br>
      <input type=button data-icon="plus" value="Save" onClick="saveFeature()">
    </div>
  </div>
__HTML
  
  print $html;
}


sub deleteFeature {
  my ($dbh, $feature_id) = @_;
  my ($ok, $msg, $icon_file, $program_file);
  
  ($icon_file, $program_file) = getFeatureDetails($dbh, $feature_id);
  
  ($ok, $msg) = deleteFeatureRecords($dbh, $feature_id);
  if ($ok) {
    unlink $icon_file;
    unlink $program_file;
  }
  
  return ($ok, $msg);
}


sub getFeatureDetails {
  my ($dbh, $feature_id) = @_;
  my ($sql, $sth, $icon_url, $program_url, $icon_file, $program_file);
  
  $sql = <<__SQL;
  SELECT feature_url, feature_icon
    FROM feature_store
    WHERE feature_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($feature_id)) {
    ($program_url, $icon_url) = $sth->fetchrow_array();    
    $program_file = $PDA_TOOLS_PATH . '/' . extractFileName($program_url);
    $icon_file = $PDA_IMG_PATH . '/' . extractFileName($icon_url);
  }
  $sth->finish;
  
  return ($icon_file, $program_file);
}


sub deleteFeatureRecords {
  my ($dbh, $feature_id) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {       # Defined on sm_db.pl
    ($ok, $msg) = deleteRecordFromFeatureStore($dbh, $feature_id);
    
    if ($ok) {
      ($ok, $msg) = deleteRecordFromFeatureList($dbh, $feature_id);
    }
    
    if ($ok) {
      commitTransaction($dbh);        # Defined on sm_db.pl
    }
    else {
      rollbackTransaction($dbh);      # Defined on sm_db.pl
    }
  }
  else {
    $msg = "Unable to start SQL transaction session, deletion process is aborted.";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub deleteRecordFromFeatureStore {
  my ($dbh, $feature_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM feature_store
    WHERE feature_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($feature_id)) {
    $msg = "Unable to delete feature from store (id = $feature_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub deleteRecordFromFeatureList {
  my ($dbh, $feature_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM feature_list
    WHERE feature_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($feature_id)) {
    $msg = "Unable to delete feature from list (id = $feature_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);  
}


sub getFeatureFromStore {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT a.feature_id, a.feature_url, a.feature_icon, b.feature_id AS is_on_list
    FROM feature_store a LEFT OUTER JOIN feature_list b ON a.feature_id = b.feature_id
    ORDER BY a.feature_id  
__SQL

  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      my $is_on_list = $data[3] + 0;
      push @result, {'id' => $data[0], 'url' => $data[1], 'icon' => $data[2], 'is_on_list' => $is_on_list};
    }
  }
  $sth->finish;
  
  return @result;
}


sub printFeatureList {
  my ($feature_list_ref) = @_;
  my ($html, @feature_list);
  
  @feature_list = @$feature_list_ref;
  
  $html = <<__HTML;
  <form id="frm_feature" name="frm_feature" action="" method="post" data-ajax="false">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="feature_id" name="feature_id" value="0">
  
  <div data-role="page" style="background-color:$PDA_BG_COLOR">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/tools/select_tools.pl" data-icon="back" style="ui-btn-left" data-ajax="false">Back</a>
      <h1>Feature Setup</h1>
    </div>
  
    <div data-role="content" style="ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed;">
      <thead>
        <tr style="background-color:lightblue">
          <td width=20% align=center><b>Icon</b></td>
          <td width=55% align=center><b>Program File</b></td>
          <td align=center><b>Delete</b></td>
        </tr>
      </thead>
      
      <tbody>
__HTML
  
  foreach my $rec (@feature_list) {
    my $this_id = $rec->{'id'};
    my $this_file = extractFileName($rec->{'url'});
    my $this_icon = $rec->{'icon'};
    my $this_row_color = ($rec->{'is_on_list'} > 0)? 'lightyellow' : 'lightgray';
    
    $html .= <<__HTML;
    <tr style="background-color:$this_row_color">
      <td align=center><img src="$this_icon" width="30px" onClick="editFeature($this_id)"></td>
      <td style="word-wrap:break-word;"><a href="javascript:editFeature($this_id)">$this_file</td>
      <td align=center><input type=button data-icon="delete" data-iconpos="notext" onClick="deleteFeature($this_id)"></td>
    </tr>
__HTML
  }
  
  $html .= <<__HTML;
        <tr style="background-color:lightblue">
          <td colspan=3 align=center>End</td>
        </tr>
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center><input type=button value="Add Feature" data-icon="plus" onClick="addFeature()"></td>
        </tr>
      </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML
  
  print $html;
}


sub extractFileName {
  my ($url) = @_;
  my ($result, @parts);
  
  @parts = split('\/', $url);
  
  if (scalar(@parts) > 0) {
    $result = allTrim($parts[scalar(@parts)-1]);
  }
  else {
    #-- No '/' character on $url --#
    $result = allTrim($url);
  }
    
  return $result;
}
