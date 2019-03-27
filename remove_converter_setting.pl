#!/usr/bin/perl

##########################################################################################
# Program: remove_converter_setting.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-27      DW              Remove system setting 'audio_converter' as
#                                               user don't install FFmpeg audio converter.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;             # Defined on sm_webenv.pl

my $sys_key = 'audio_converter';
my $dbh;

$dbh = dbconnect($COOKIE_MSG);

if ($dbh) {
  my ($ok, $msg) = deleteSysSetting($dbh, $sys_key);
  if (!$ok) {
    print "$msg\n";
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
  $sth->finish;
  
  return ($ok, $msg);
}
