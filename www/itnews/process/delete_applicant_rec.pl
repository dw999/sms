#!/usr/bin/perl
##########################################################################################
# Program: delete_applicant_rec.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2018-07-23      AY              Remove timeout, rejected, and completed applicant
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
