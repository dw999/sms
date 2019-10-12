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
# Program: /www/itnews/cgi-pl/admin/maintain_file_types.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-10-06      DW              Maintain a list of file types which are used
#                                               to handle uploaded audio and video files
#                                               playing and conversion.
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

my $op = paramAntiXSS('op');                               # A = Add, E = Edit, D = Delete.
my $oper_mode = paramAntiXSS('oper_mode');                 # S = Save, others go to input form.
my $ftype_id = paramAntiXSS('ftype_id');                   # Unique ID of file type.
my $file_ext = paramAntiXSS('file_ext');                   # File extension.
my $file_type = paramAntiXSS('file_type');                 # File type.

my $dbh = dbconnect($COOKIE_MSG);                          
my %user_info = printHead($COOKIE_MSG);                    # Defined on sm_webenv.pl
my $user_id = $user_info{'USER_ID'} + 0;
my @ftype_list = ();                                       # List of defined file types.
my @file_types = ();                                       # Existing file types which can be selected.
my %ftype_dtl;

printJavascriptSection();

if (isHeSysAdmin($dbh, $user_id)) {                        # Defined on sm_user.pl 
  if ($op eq 'A') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = addNewFileType($dbh, $file_ext, $file_type);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_file_types.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_file_types.pl?op=A");
      }        
    }
    else {
      @file_types = getExistFileTypes($dbh);
      printNewFileTypeForm(\@file_types);
    }
  }
  elsif ($op eq 'E') {
    if ($oper_mode eq 'S') {
      my ($ok, $msg) = modifyFileType($dbh, $ftype_id, $file_ext, $file_type);
      if ($ok) {
        redirectTo("/cgi-pl/admin/maintain_file_types.pl");
      }
      else {
        alert($msg);
        redirectTo("/cgi-pl/admin/maintain_file_types.pl?op=E");
      }        
    }
    else {
      @file_types = getExistFileTypes($dbh);
      %ftype_dtl = getFileTypeDetails($dbh, $ftype_id);
      printFileTypeEditForm(\%ftype_dtl, \@file_types);
    }  
  }
  elsif ($op eq 'D') {
    my ($ok, $msg) = deleteFileType($dbh, $ftype_id);
    if (!$ok) {
      alert($msg);
    }  
    redirectTo("/cgi-pl/admin/maintain_file_types.pl");
  }
  else {
    @ftype_list = getFileTypeList($dbh);
    printFileTypeList(\@ftype_list); 
  }
}
else {
  #-- Something is wrong, the system may be infiltrated by hacker. Expel the suspicious user. --#
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
  <script src="/js/jquery-editable-select.min.js"></script>
  <link href="/js/jquery-editable-select.min.css" rel="stylesheet">  
  <script src="/js/common_lib.js"></script>

  <script>
    function goBack() {
      window.location.href = "/cgi-pl/admin/system_setup.pl";
    }
  
    function goHome() {
      window.location.href = "/cgi-pl/msg/message.pl";
    }
    
    function addFileType() {
      document.getElementById("op").value = "A";
      document.getElementById("frm_file_type").submit();          
    }
    
    function editFileType(ftype_id) {
      document.getElementById("op").value = "E";
      document.getElementById("ftype_id").value = ftype_id;
      document.getElementById("frm_file_type").submit();      
    }
    
    function deleteFileType(ftype_id) {
      if (confirm("Are you sure to delete this file type?")) {
        document.getElementById("op").value = "D";
        document.getElementById("ftype_id").value = ftype_id;
        document.getElementById("frm_file_type").submit();
      }
    }
    
    function saveFileType() {
      var file_ext = allTrim(\$('#file_ext').val());
      var file_type = allTrim(\$('#file_type').val());
      
      if (file_ext == "") {
        alert("Please input file extension before saving");
        \$('#file_ext').focus();
        return false;
      }
      
      if (file_ext == "") {
        alert("Please input file type before saving");
        \$('#file_type').focus();
        return false;
      }      
            
      \$('#oper_mode').val("S");
      \$('#frm_file_type').submit();      
    }
  </script>
__JS
}


sub addNewFileType {
  my ($dbh, $file_ext, $file_type) = @_;
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  $ftype_id = isFileTypeExist($dbh, $file_ext);        
  
  if ($ftype_id > 0) {
    ($ok, $msg) = updateFileType($dbh, $ftype_id, $file_ext, $file_type);
  }
  else {
    ($ok, $msg) = addFileType($dbh, $file_ext, $file_type);
  }
  
  return ($ok, $msg);
}


sub isFileTypeExist {
  my ($dbh, $file_ext) = @_;
  my ($sql, $sth, $cnt, $result);
  
  $sql = <<__SQL;
  SELECT ftype_id
    FROM file_type
    WHERE file_ext = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($file_ext)) {
    ($result) = $sth->fetchrow_array();
    $result += 0;
  }
  else {
    $result = 0;
  }
  $sth->finish;
  
  return $result;
}


sub updateFileType {
  my ($dbh, $ftype_id, $file_ext, $file_type) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE file_type
    SET file_ext = ?,
        file_type = ?
    WHERE ftype_id = ?    
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($file_ext, $file_type, $ftype_id)) {
    $msg = "Unable to update file type record for $file_ext. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub addFileType {
  my ($dbh, $file_ext, $file_type) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO file_type
  (file_ext, file_type)
  VALUES
  (?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($file_ext, $file_type)) {
    $msg = "Unable to add file type record for $file_ext. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getExistFileTypes {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT DISTINCT file_type
    FROM file_type
    ORDER BY file_type
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my ($this_file_type) = $sth->fetchrow_array()) {
      push @result, $this_file_type;
    }    
  }
  
  return @result;
}


sub printNewFileTypeForm {
  my ($file_types_ref) = @_;
  my ($html, $file_type_options, @file_types);
  
  @file_types = @$file_types_ref;
  
  $file_type_options = "";
  foreach my $this_file_type (@file_types) {
    $file_type_options .= <<__HTML;
    <option>$this_file_type</option>
__HTML
  }
  
  $html = <<__HTML;
  <form id="frm_file_type" name="frm_file_type" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/admin/maintain_file_types.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Add File Type</h1>
    </div>
    
    <div data-role="main" class="ui-body-d ui-content">
      <label for="file_ext">File Ext.:</label>
      <input type=text id="file_ext" name="file_ext" value="$file_ext" maxlength=16>
      <label for="file_type">File Type:</label>
      <select id="file_type" name="file_type">
        $file_type_options
      </select>      
      <script>
        //*-- Activate editable selection for input object 'file_type' --*// 
        \$('#file_type').editableSelect({
          effects: 'slide',
          duration: 200
        });
      </script>
      <br>
      <input type=button id="save" name="save" Value="Save" onClick="saveFileType()">
      <br>
      <b>Remark:</b><br>
      You may add new file type or select existing file type from the list.
    </div>    
  </div>
  </form>
__HTML
  
  print $html;
}


sub modifyFileType {
  my ($dbh, $ftype_id, $file_ext, $file_type) = @_;
  my ($ok, $msg, $new_ftype_id);
  
  $ok = 1;
  $msg = '';
  
  $new_ftype_id = isFileTypeExist($dbh, $file_ext);        
  
  if ($new_ftype_id == $ftype_id) {
    #-- File extension is remain unchanged --#
    ($ok, $msg) = updateFileType($dbh, $ftype_id, $file_ext, $file_type);
  }
  else {
    if ($new_ftype_id > 0) {
      #-- File extension is changed, and the file type record of the amended file extension has already existed. --#
      if (startTransaction($dbh)) {
        ($ok, $msg) = deleteFileType($dbh, $ftype_id);
        
        if ($ok) {
          ($ok, $msg) = updateFileType($dbh, $new_ftype_id, $file_ext, $file_type);
        }
        
        if ($ok) {
          commitTransaction($dbh);
        }
        else {
          rollbackTransaction($dbh);
        }
      }
      else {
        $msg = "Unable to start SQL transaction session, file type record cannot be updated.";
        $ok = 0;
      }      
    }
    else {
      #-- File extension is changed, and the file type record of the amended file extension does not exist. --#
      ($ok, $msg) = updateFileType($dbh, $ftype_id, $file_ext, $file_type);
    }
  }
  
  return ($ok, $msg);
}


sub getFileTypeDetails {
  my ($dbh, $ftype_id) = @_;
  my ($sql, $sth, @data, %result);
  
  $sql = <<__SQL;
  SELECT file_ext, file_type
    FROM file_type
    WHERE ftype_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute($ftype_id)) {
    @data = $sth->fetchrow_array();
    %result = ('file_ext' => $data[0], 'file_type' => $data[1]);
  }
  
  return %result;
}

sub printFileTypeEditForm {
  my ($ftype_dtl_ref, $file_types_ref) = @_;
  my ($html, $file_type_options, %ftype_dtl, @file_types);
  
  %ftype_dtl = %$ftype_dtl_ref;
  @file_types = @$file_types_ref;
  
  $file_type_options = '';
  foreach my $this_file_type (@file_types) {
    my $selected = ($this_file_type eq $ftype_dtl{'file_type'})? 'selected' : '';
    $file_type_options .= "<option $selected>$this_file_type</option>";    
  }
  
  $html = <<__HTML;
  <form id="frm_file_type" name="frm_file_type" action="" method="post">
  <input type=hidden id="op" name="op" value="$op">
  <input type=hidden id="oper_mode" name="oper_mode" value="">
  <input type=hidden id="ftype_id" name="ftype_id" value="$ftype_id">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="/cgi-pl/admin/maintain_file_types.pl" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>Edit File Type</h1>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <label for="file_ext">File Ext.:</label>
      <input type=text id="file_ext" name="file_ext" value="$ftype_dtl{'file_ext'}" maxlength=16>
      <label for="file_type">File Type:</label>
      <select id="file_type" name="file_type">
        $file_type_options
      </select>      
      <script>
        //*-- Activate editable selection for input object 'file_type' --*// 
        \$('#file_type').editableSelect({
          effects: 'slide',
          duration: 200
        });
      </script>
      <br>
      <input type=button id="save" name="save" Value="Save" onClick="saveFileType()">
      <br>
      <b>Remark:</b><br>
      You may add new file type or select existing file type from the list.
    </div>
  </div>
  </form>
__HTML
  
  print $html
}


sub deleteFileType {
  my ($dbh, $ftype_id) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM file_type
    WHERE ftype_id = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($ftype_id)) {
    $msg = "Unable to delete file type record (id: $ftype_id). Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub getFileTypeList {
  my ($dbh) = @_;
  my ($sql, $sth, @result);
  
  $sql = <<__SQL;
  SELECT ftype_id, file_ext, file_type
    FROM file_type
    ORDER BY file_type, file_ext
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      push @result, {'ftype_id' => $data[0], 'file_ext' => $data[1], 'file_type' => $data[2]};
    }    
  }
  $sth->finish;
  
  return @result;
}


sub printFileTypeList {
  my ($ftype_list_ref) = @_;
  my ($html, @ftype_list);
  
  @ftype_list = @$ftype_list_ref;
  
  $html = <<__HTML;
  <form id="frm_file_type" name="frm_file_type" action="" method="post">
  <input type=hidden id="op" name="op" value="">
  <input type=hidden id="ftype_id" name="ftype_id" value="">
  
  <div data-role="page">
    <div data-role="header" data-position="fixed" data-tap-toggle="false">
      <a href="javascript:goBack()" data-icon="back" class="ui-btn-left" data-ajax="false">Back</a>
      <h1>File Types</h1>
      <a href="javascript:goHome()" data-icon="home" class="ui-btn-right" data-ajax="false">Home</a>
    </div>
  
    <div data-role="main" class="ui-body-d ui-content">
      <table width=100% cellspacing=1 cellpadding=1 style="table-layout:fixed;">
      <thead>
        <tr style="background-color:lightblue">
          <td width=30% align=center valign=center><b>File Ext.</b></td>
          <td width=50% align=center valign=center><b>File Type</b></td>
          <td align=center valign=center><b>Delete</b></td>
        </tr>
      </thead>      
      <tbody>
__HTML

  foreach my $rec (@ftype_list) {
    my $this_ftype_id = $rec->{'ftype_id'} + 0;
    my $this_file_ext = $rec->{'file_ext'};
    my $this_file_type = $rec->{'file_type'};
    
    $html .= <<__HTML;
        <tr style="background-color:lightyellow">
          <td align=center valign=center style="word-wrap:break-word;"><a href="javascript:editFileType($this_ftype_id)">$this_file_ext</a></td>
          <td align=center valign=center style="word-wrap:break-word;"><a href="javascript:editFileType($this_ftype_id)">$this_file_type</a></td>
          <td align=center valign=center><input type=button id="del_ft" name="del_ft" data-icon="delete" data-iconpos="notext" onClick="deleteFileType($this_ftype_id)"></td>
        </tr>
__HTML
  }

  $html .= <<__HTML;
        <tr style="background-color:lightblue">
          <td align=center valign=center colspan=3>End</td>  
        </tr>
      </tbody>
      </table>
    </div>
    
    <div data-role="footer" data-position="fixed" data-tap-toggle="false">
      <table width=100% cellspacing=0 cellpadding=0>
      <thead></thead>
      <tbody>
        <tr>
          <td align=center valign=center><input type=button id="add_ft" name="add_ft" value="Add File Type" data-icon="plus" onClick="addFileType()"></td>
        </tr> 
      </tbody>
      </table>
    </div>
  </div>
  </form>
__HTML

  print $html;
}
