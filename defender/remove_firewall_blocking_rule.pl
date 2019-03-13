#!/usr/bin/perl
##########################################################################################
# Program: remove_firewall_blocking_rule.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2017-01-30      AY              Remove IP address blocking rules on firewall
#                                               which exceed a pre-defined period.
##########################################################################################

use strict;
use warnings;
use DBI;

my $dsn;                # Database configuration.  
my $dbh;                # Database connection handle. 
my $database = 'defendb';  # Database for the table to store hackers' IP addresses.
my $host = 'localhost'; # Permitted connection hostname of this database.  
my $user = 'secure';    # Database user name.
my $pass = 'Txf742kp4M';  # Database password.
my $cnt = 0;
my $error = 0;
my $err_msg = '';
my $hacker_ip_block_days = 1;    # Day(s) that hacker's IP addresses will be blocked. Max. blocking days is 1825.
my @ip_list = ();


print "Processing....\n";

$dsn = "DBI:mysql:database=$database;host=$host;";
$dbh = DBI->connect($dsn, $user, $pass, {'RaiseError' => 1});

@ip_list = getOldHackerIpList($hacker_ip_block_days);

foreach my $this_hacker_ip (@ip_list) {
  my $ok = removeFirewallBlockingRule($this_hacker_ip);
  if ($ok != -1) {
    print "$this_hacker_ip has been removed from firewall blocking rule.\n";
    markHackerIpInactive($this_hacker_ip);
    $cnt++;
  }  
  else {
    $err_msg .= "Unable to remove firewall blocking rule for IP address $this_hacker_ip \n";
    $error = 1; 
  }
}

if ($error) {
  print "$err_msg";
}
else {
  if ($cnt > 0) {
    my $ok = reloadFirewall();    
    if ($ok == -1) {
      print "$cnt blocking IP address(es) is/are removed, but rules of the firewall cannot be refreshed.\n";
    }
    else {
      print "$cnt blocking IP address(es) is/are removed. \n";
    } 
  }
  else {
    print "No need to refresh rules of the firewall.\n";
  }
}

$dbh->disconnect;
#-- End Main Section --#


sub getOldHackerIpList {
  my ($hacker_ip_block_days) = @_;
  my ($sql, $sth, $lower_block_date, @data, @result);

  #-- Step 1: Determine the releasing date --#
  $sql = "SELECT FROM_DAYS(TO_DAYS(SYSDATE()) - $hacker_ip_block_days)";
  $sth = $dbh->prepare($sql);
  $sth->execute();
  @data = $sth->fetchrow_array();
  $lower_block_date = allTrim($data[0]);
  $sth->finish();

  #-- Step 2: Get all hacker IP addresses on or older than this date --#
  $sql = "SELECT ipv4_address " .
         "  FROM hacker_ip " .
         "  WHERE hit_date <= '$lower_block_date' " .
         "    AND is_active = 1 ";
         
  $sth = $dbh->prepare($sql);
  $sth->execute();
  while (@data = $sth->fetchrow_array()) {
    push @result, $data[0];
  }
  $sth->finish();
         
  return @result; 
}


sub removeFirewallBlockingRule {
  my ($hacker_ip) = @_;
  my ($cmd, $ok); 
  
  $cmd = <<__CMD;
  firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$hacker_ip' reject"
__CMD

  $ok = system($cmd); 
  
  return $ok;
}  


sub markHackerIpInactive {
  my ($hacker_ip) = @_;
  my ($sql, $sth);
  
  $sql = "UPDATE hacker_ip " .
         "  SET is_active = 0 " .
         "  WHERE ipv4_address = ?";
         
  $sth = $dbh->prepare($sql);
  $sth->execute($hacker_ip);
  $sth->finish();  
}  


sub reloadFirewall {
  my ($cmd, $ok); 
  
  $cmd = <<__CMD;
  firewall-cmd --reload
__CMD

  $ok = system($cmd); 
  
  return $ok;
}


sub allTrim {
  my ($str) = @_;
  
  $str =~ s/\s+$//;      # Right trim
  $str =~ s/^\s+//;      # Left trim
  
  return $str;
}

