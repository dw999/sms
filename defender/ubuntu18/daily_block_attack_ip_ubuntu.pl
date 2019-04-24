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
# Program: daily_block_attack_ip_ubuntu.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2019-04-18      DW              System attacking monitoring and hacker IP
#                                               addresses blocking for Ubuntu 18.04.
#                                               Note: 1. Using built-in firewall UFW is assumed.
#                                                     2. Firewall and this Perl script is placed
#                                                        on same machine.
#                                                     3. It is based on daily_block_attack_ip_centos7.pl,
#                                                        but firewall control commands.
#
# Remark: Database schema is as follows:
#         
#         CREATE DATABASE defendb
#           DEFAULT CHARACTER SET utf8
#           DEFAULT COLLATE utf8_general_ci;
#
#         GRANT ALL ON defendb.* TO 'secure'@localhost IDENTIFIED BY 'Txf742kp4M';
#
#         CREATE TABLE hacker_ip
#         (
#           ipv4_address varchar(20),
#           ipv6_address varchar(255),
#           hit_date date,
#           is_active int
#         ) ENGINE=InnoDB DEFAULT CHARSET=utf8; 
##########################################################################################

use strict;
use DBI;

my $workfile = "/tmp/secure" . allTrim(sprintf("%.0f", rand(2000))) . ".txt";
my $dsn;                # Database configuration.  
my $dbh;                # Database connection handle. 
my $database = 'defendb';  # Database for the table to store hackers' IP addresses.
my $host = 'localhost'; # Permitted connection hostname of this database.  
my $user = 'secure';    # Database user name.
my $pass = 'Txf742kp4M';  # Database password.
my $cnt = 0;
my $error = 0;          # Error flag.
my $err_msg = '';       # Error message.
my %reserved_ip;        # Reserved IP list that would not considered as attacker.


print "Start Date/Time: " . getCurrentDate(1) . "\n\n";

my $ok = system('cp /var/log/auth.log ' . $workfile);

if ($ok != -1) {
  %reserved_ip = fillReservedIpAddress();

  #-- Connect database --#
  $dsn = "DBI:mysql:database=$database;host=$host;";
  $dbh = DBI->connect($dsn, $user, $pass, {'RaiseError' => 1});

  open FILE, "<", $workfile or die("Unable to open the file $workfile \n");
  while (<FILE>) {
    my $this_line = $_;
    
    if (attackVectorIsFound($this_line)) {   
      my $this_hacker_ip = getHackerIpAddress($this_line);
      my $this_reserved_ip = $reserved_ip{$this_hacker_ip} + 0;
    
      if (allTrim($this_hacker_ip) ne '' && $this_reserved_ip != 1) {
        if (!isActiveHackerIpExist($this_hacker_ip)) {
          my $add_firewall_rule_ok = addBlockingRuleToFirewall($this_hacker_ip);

          if ($add_firewall_rule_ok != -1) {
            if (isHackerIpExist($this_hacker_ip)) {
              updateAttackDate($this_hacker_ip);
            }
            else {
              saveHackerIp($this_hacker_ip);      
            }
            
            $cnt++;  
          }  
          else {
            $err_msg .= "Error 1: Unable to add blocking rule of hacker IP address $this_hacker_ip, check for it.\n";
            $error = 1; 
          }                
        }    
        else {
          updateAttackDate($this_hacker_ip);
        }
      }
    }
  }
  
  if ($cnt > 0) {
    print "$cnt hacker IP address(es) is/are added.\n";
  }
  else {
    print "No need to refresh firewall\n";
  }

  $dbh->disconnect;  
  close(FILE);
  unlink $workfile;
}
else {
  $err_msg = "Error 0: Unable to make a temporary working copy of the access log, check for it.\n";
  $error = 1; 
}

if ($error == 1) {
  print "$err_msg \n";
}

print "\nFinish Date/Time: " . getCurrentDate(1) . "\n\n";
#-- End Main Section --#


sub fillReservedIpAddress {
  my ($i, $this_ip, %result, @c_class);
  
  $result{'127.0.0.1'} = 1;
  
  #-- Protect common internal IP addresses --#
  for ($i = 0; $i <= 254; $i++) {
    $this_ip = "192.168.0.$i";
    $result{$this_ip} = 1;
    $this_ip = "192.168.1.$i";
    $result{$this_ip} = 1;
  }
  
  return %result;
}


sub getCurrentDate {
  my ($show_time) = @_;
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $ydat, $isdst) = localtime();
  my ($date_part, $time_part);
  
  $show_time += 0;
  $year += 1900;
  $mon++;
  $date_part = sprintf("%04d", $year) . '-' . sprintf("%02d", $mon) . '-' . sprintf("%02d", $mday);
  $time_part = ($show_time > 0)? sprintf("%02d", $hour). ':' . sprintf("%02d", $min) . ':' . sprintf("%02d", $sec) : '';
  $date_part .= ' ' . $time_part;
  
  return $date_part;
}


sub attackVectorIsFound {
  my ($this_line) = @_;
    
  if ($this_line =~ /Failed password/) {
    return 1;
  }  
    
  if ($this_line =~ /Invalid user/) {
    return 1;  
  }
  
  if ($this_line =~ /authentication failure/) {
    return 1;
  }
  
  if ($this_line =~ /POSSIBLE BREAK-IN ATTEMPT/) {
    return 1;
  }
  
  if ($this_line =~ /Did not receive identification string/) {
    return 1;
  }
  
  if ($this_line =~ /Bad protocol version identification/) {
    return 1;
  }
  
  if ($this_line =~ /sshd/ && $this_line =~ /Received disconnect from/ && $this_line =~ /[preauth]/) {
    return 1;
  }

  return 0;
}


sub getHackerIpAddress {
  my ($this_line) = @_;
  my ($ip_address, @data);

  @data = split(' ', $this_line);
  foreach my $str (@data) {
    if ($str =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/) {
      $ip_address = $1;
      last;
    }  
  }    
  
  return $ip_address;
}


sub isActiveHackerIpExist {
  my ($hacker_ip) = @_;
  my ($sql, $sth, $cnt, $result, @data);
  
  $sql = "SELECT COUNT(*) AS cnt FROM hacker_ip WHERE ipv4_address = '$hacker_ip' AND is_active = 1";
  $sth = $dbh->prepare($sql);
  $sth->execute();
  @data = $sth->fetchrow_array();
  $cnt = $data[0] + 0;
  $result = ($cnt > 0)? 1 : 0;
  $sth->finish();
  
  return $result;  
}


sub isHackerIpExist {
  my ($hacker_ip) = @_;
  my ($sql, $sth, $cnt, $result, @data);
  
  $sql = "SELECT COUNT(*) AS cnt FROM hacker_ip WHERE ipv4_address = '$hacker_ip'";
  $sth = $dbh->prepare($sql);
  $sth->execute();
  @data = $sth->fetchrow_array();
  $cnt = $data[0] + 0;
  $result = ($cnt > 0)? 1 : 0;
  $sth->finish();
  
  return $result;
}  


sub addBlockingRuleToFirewall {
  my ($hacker_ip) = @_;
  my ($cmd, $ok); 
  
  $cmd = <<__CMD;
  ufw deny from $hacker_ip
__CMD

  $ok = system($cmd); 
  
  return $ok;
}


sub saveHackerIp {
  my ($hacker_ip) = @_;
  my ($sql, $sth);
  
  $sql = "INSERT INTO hacker_ip (ipv4_address, hit_date, is_active) VALUES (?, SYSDATE(), 1)";
  $sth = $dbh->prepare($sql);
  $sth->execute($hacker_ip);
  $sth->finish();
}


sub updateAttackDate {
  my ($hacker_ip) = @_;
  my ($sql, $sth);

  $sql = "UPDATE hacker_ip " .
         "  SET hit_date = SYSDATE(), " .
         "      is_active = 1 " .
         "  WHERE ipv4_address = ?";
 
  $sth = $dbh->prepare($sql);
  $sth->execute($hacker_ip);
  $sth->finish();  
}


sub allTrim {
  my ($str) = @_;
  
  $str =~ s/\s+$//;      # Right trim
  $str =~ s/^\s+//;      # Left trim
  
  return $str;
}


