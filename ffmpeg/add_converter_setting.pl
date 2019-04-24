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
# Program: add_converter_setting.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-27      DW              Configure system setting 'audio_converter' 
#                                               after FFmpeg audio converter is built.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;             # Defined on sm_webenv.pl

my $sys_key = 'audio_converter';
my $sys_value = "/usr/bin/ffmpeg -i '{input_file}' '{output_file}'";
my $dbh;

$dbh = dbconnect($COOKIE_MSG);

if ($dbh) {
  my ($ok, $msg);
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = deleteSysSetting($dbh, $sys_key);
    
    if ($ok) {
      ($ok, $msg) = addSysSetting($dbh, $sys_key, $sys_value);
    }
    
    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
      print "$msg\n";  
    }
  }
  else {
    print "Unable to start SQL transaction session, process is aborted.\n"; 
  }
}
else {
  print "Unable to connect to the database, process is aborted.\n";
}

dbclose($dbh);
#-- End Main Section --#


sub deleteSysSetting {
  my ($dbh, $sys_key) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM sys_settings
    WHERE sys_key = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sys_key)) {
    $msg = "Unable to delete system setting '$sys_key'. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub addSysSetting {
  my ($dbh, $sys_key, $sys_value) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  INSERT INTO sys_settings
  (sys_key, sys_value)
  VALUES
  (?, ?)
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sys_key, $sys_value)) {
    $msg = "Unable to create system settings for audio converter 'FFmpeg', you may add it manually. Error: " . $sth->errstr . "\n\n" .
           "$sys_key --> $sys_value \n";
    $ok = 0;       
  }
  $sth->finish;
  
  return ($ok, $msg);
}

