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
# Program: remove_firewall_blocking_rule.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2017-01-30      DW              Remove IP address blocking rules on firewall
#                                               which exceed a pre-defined period.
# V1.0.01       2020-04-21      DW              Add parameter "--zone=public" to IP address
#                                               blocking removal command.
# V1.0.02       2021-07-23      DW              Improve function 'getOldHackerIpList' to let 
#                                               time calculation precise to hour.
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
my $hacker_ip_block_days = 2;    # Day(s) that hacker's IP addresses will be blocked. Max. blocking days is 1825.
my @ip_list = ();


print "Processing....\n";

$dsn = "DBI:mysql:database=$database;host=$host;";
$dbh = DBI->connect($dsn, $user, $pass, {'RaiseError' => 1});

@ip_list = getOldHackerIpList($hacker_ip_block_days);

foreach my $this_hacker_ip (@ip_list) {
  my $ok = removeFirewallBlockingRule($this_hacker_ip);
  if ($ok != -1) {
    print "$this_hacker_ip is removed from firewall blocking rule.\n";
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
  my ($sql, $sth, $block_hours, @data, @result);

  #-- Convert blocking days to hours --#
  $block_hours = $hacker_ip_block_days * 24;
  
  $sql = "SELECT ipv4_address " .
         "  FROM hacker_ip " .
         "  WHERE TIMESTAMPDIFF(hour, hit_date, CURRENT_TIMESTAMP()) >= $block_hours " .
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
  firewall-cmd --permanent --zone=public --remove-rich-rule="rule family='ipv4' source address='$hacker_ip' reject"
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

