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
# Program: delete_applicant_rec.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-23      DW              Remove timeout, rejected, and completed applicant
#                                               records.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_msglib.pl";

our $COOKIE_MSG;                      # Defined on sm_webenv.pl

my $cookie_name = $COOKIE_MSG;      
my $dbh = dbconnect($cookie_name);

if ($dbh ne undef) {
  #-- Step 1: Remove those rejected and completed applicant records first --#
  removeRejectAndCompletedRecords($dbh);  
  #-- Step 2: Then delete all timeout records (i.e. more than 7 days of applied date) --#
  removeTimeoutRecords($dbh);
}

dbclose($dbh);
#-- End Main Section --#


sub removeRejectAndCompletedRecords {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM applicant
    WHERE status IN ('R', 'C', 'T')
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove rejected and completed applicant records. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub removeTimeoutRecords {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  DELETE FROM applicant
    WHERE DATEDIFF(CURRENT_TIMESTAMP(), apply_date) >= 7
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove applicant records beyond 7 days. Error: " . $sth->errstr;
    $ok = 0;
  }
  
  return ($ok, $msg);  
}
