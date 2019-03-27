#!/usr/bin/perl

##########################################################################################
# Program: input_sms_data.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-13      DW              Get important data for SMS server setup. It
#                                               is part of SMS installation program.
# V1.0.01       2019-01-20      DW              Add connection mode input. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;             # Defined on sm_webenv.pl

my $connect_mode = 0;
my $decoy_site_dns = '';
my $msg_site_dns = '';
my $sa_email = '';
my $tx_gmail = '';
my $tx_username = '';
my $tx_password = '';
my $stop_run = 0;
my $dbh;

$dbh = dbconnect($COOKIE_MSG);

if ($dbh) {
  while (!$stop_run) {
    print "Connection mode (0, 1, 2 or 3): ";
    $connect_mode = <STDIN>;
    chomp $connect_mode;
    
    print "Decoy site domain name (e.g. https://decoy-site.com): ";
    $decoy_site_dns = <STDIN>;
    chomp $decoy_site_dns;
  
    print "Messaging site domain name (e.g. https://messaging-site.net): ";
    $msg_site_dns = <STDIN>;
    chomp $msg_site_dns;
  
    print "Email address of SMS administrator: ";
    $sa_email = <STDIN>;
    chomp $sa_email;
  
    print "Worker Gmail address of SMS: ";
    $tx_gmail = <STDIN>;
    chomp $tx_gmail; 
  
    print "Username of the worker Gmail account: ";
    $tx_username = <STDIN>;
    chomp $tx_username;

    print "Password of the worker Gmail account: ";
    $tx_password = <STDIN>;
    chomp $tx_password;
  
    print "\nYou have input the following data:\n";
    print "-------------------------------------------------\n";
    print "Connection mode: $connect_mode\n";
    print "Decoy site domain name: $decoy_site_dns\n";
    print "Messaging site domain name: $msg_site_dns\n";
    print "Email address of SMS administrator: $sa_email\n";
    print "Worker Gmail address of SMS: $tx_gmail\n";
    print "Username of the worker Gmail account: $tx_username\n";
    print "Password of the worker Gmail account: $tx_password\n";
    print "-------------------------------------------------\n\n";    
    print "Is it correct (Y/N)? ";
    my $yn = <STDIN>;
    chomp $yn;
    
    if (uc($yn) eq 'Y') {
      my ($ok, $msg) = updateSMS();
      if ($ok) {
        print "SMS server setup data is saved successfully.\n";
        $stop_run = 1;
      }
      else {
        print "$msg\n\n";
        print "Do you want to try again (Y/N)? ";
        $yn = <STDIN>;
        chomp $yn;
        if (uc($yn) eq 'N') {
          $stop_run = 1;
        }
      }
    }
    else {
      print "\n\n";
    }
  }
}
else {
  print "Unable to connect to the database, process is aborted.\n";
}

dbclose($dbh);


sub updateSMS {
  my ($ok, $msg);
  
  $ok = 1;
  $msg = '';
  
  if (startTransaction($dbh)) {
    ($ok, $msg) = updateConnectionMode($dbh, $connect_mode);
    
    if ($ok) {
      ($ok, $msg) = updateDecoySite($dbh, $decoy_site_dns);      
    }
      
    if ($ok) {
      ($ok, $msg) = updateMessagingSite($dbh, $msg_site_dns);
    }
  
    if ($ok) {
      ($ok, $msg) = updateAdminEmail($dbh, $sa_email);
    }
  
    if ($ok) {
      ($ok, $msg) = addWorkerGmailAccount($dbh, $tx_gmail, $tx_username, $tx_password);
    }

    if ($ok) {
      commitTransaction($dbh);
    }
    else {
      rollbackTransaction($dbh);
    }
  }
  else {
    $msg = "Unable to start SQL transaction session, SMS server setup data is unable to be saved.\n";
    $ok = 0;
  }
  
  return ($ok, $msg);
}


sub updateConnectionMode {
  my ($dbh, $connect_mode) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';  
  $connect_mode = sprintf("%d", $connect_mode + 0);
  
  $sql = <<__SQL;
  DELETE FROM sys_settings
    WHERE sys_key = 'connection_mode'
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove old SMS connection mode. Error: " . $sth->errstr;
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    $sql = <<__SQL;
    INSERT INTO sys_settings
    (sys_key, sys_value)
    VALUES
    ('connection_mode', ?)
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($connect_mode)) {
      $msg = "Unable to update SMS connection mode. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}


sub updateDecoySite {
  my ($dbh, $decoy_site_dns) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';

  #-- Delete decoy site domain record --#  
  $sql = <<__SQL;
  DELETE FROM sites
    WHERE site_type = 'DECOY'  
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove old decoy site domain record. Error: " . $sth->errstr . "\n";
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Add decoy site domain record --#
    $sql = <<__SQL;
    INSERT INTO sites
    (site_type, site_dns, status)
    VALUES
    ('DECOY', ?, 'A')
__SQL
 
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($decoy_site_dns)) {
      $msg = "Unable to update decoy site domain record. Error: " . $sth->errstr . "\n";
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}


sub updateMessagingSite {
  my ($dbh, $msg_site_dns) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';

  #-- Delete message site domain record --#  
  $sql = <<__SQL;
  DELETE FROM sites
    WHERE site_type = 'MESSAGE'  
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute()) {
    $msg = "Unable to remove old messaging site domain record. Error: " . $sth->errstr . "\n";
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Add messaging site domain record --#
    $sql = <<__SQL;
    INSERT INTO sites
    (site_type, site_dns, status)
    VALUES
    ('MESSAGE', ?, 'A')
__SQL
 
    $sth = $dbh->prepare($sql);
    if (!$sth->execute($msg_site_dns)) {
      $msg = "Unable to update messaging site domain record. Error: " . $sth->errstr . "\n";
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);  
}


sub updateAdminEmail {
  my ($dbh, $sa_email) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  UPDATE user_list
    SET email = ?
    WHERE user_name = 'smsadmin'
      AND STATUS = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($sa_email)) {
    $msg = "Unable to update SMS administrator's email. Error: " . $sth->errstr . "\n";
    $ok = 0;
  }
  $sth->finish;
  
  return ($ok, $msg);
}


sub addWorkerGmailAccount {
  my ($dbh, $tx_gmail, $tx_username, $tx_password) = @_;
  my ($ok, $msg, $sql, $sth);
  
  $ok = 1;
  $msg = '';

  #-- Remove old worker Gmail record, if it has already existed. --#
  $sql = <<__SQL;
  DELETE FROM sys_email_sender
    WHERE email = ?
__SQL
  
  $sth = $dbh->prepare($sql);
  if (!$sth->execute($tx_gmail)) {
    $msg = "Unable to remove old worker Gmail account $tx_gmail. Error: " . $sth->errstr . "\n";
    $ok = 0;
  }
  $sth->finish;
  
  if ($ok) {
    #-- Add worker Gmail account --#
    $sql = <<__SQL;
    INSERT INTO sys_email_sender
    (email, m_user, m_pass, smtp_server, port, status)
    VALUES
    (?, ?, ?, 'smtp.gmail.com', 587, 'A')
__SQL

    $sth = $dbh->prepare($sql);
    if (!$sth->execute($tx_gmail, $tx_username, $tx_password)) {
      $msg = "Unable to add worker Gmail account $tx_gmail. Error: " . $sth->errstr . "\n";
      $ok = 0;
    }
    $sth->finish;
  }
  
  return ($ok, $msg);
}

