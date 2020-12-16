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
# Program: daily_block_attack_ip.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     =========================
# V1.0.00       2017-01-30      DW              System attacking monitoring and hacker IP
#                                               addresses blocking for Red Hat/CentOS 7.
#                                               Note: 1. Using built-in firewall is assumed.
#                                                     2. Firewall and this Perl script are placed
#                                                        on same machine.
# V1.0.01       2017-03-03      DW              Add a new attack vector identity "Bad protocol version identification".
# V1.0.02       2017-04-16      DW              Fix a logical bug for firewall rule update.
# V1.0.03       2018-12-28      DW              Add a new attack vector identity "Received disconnect from" for sshd.
# V1.0.04       2019-05-09      DW              1. Rename to daily_block_attack_ip.pl and serve for all SMS supported 
#                                                  platforms, and assume firewalld as used firewall.
#                                               2. Use command line parameter to identify running platform, in order to
#                                                  open corresponding user authentication log file.
# V1.0.05       2019-05-11      DW              Quit process if 'remove_firewall_blocking_rule.pl' is running, in order
#                                               to avoid firewalld rules configuration file updating racing situation.
# V1.0.06       2019-05-12      DW              Quit process if another copy of 'daily_block_attack_ip.pl' is running.
# V1.0.07       2019-12-15      DW              Use system log file as source in order to increase performance.
# V1.0.08       2020-04-21      DW              Add paramter "--zone=public" to IP address blocking command, since I set
#                                               firewalld configuration "AllowZoneDrifting=no".
# V1.0.09       2020-07-22      DW              Take care Nginx web sites attacking also.
# V1.0.10       2020-12-16      DW              - Fix a bug which update the 'hit_date' of active hacker IP address constinuously.
#                                               - Add option "--quiet" to firewalld command to suppress status displaying.  
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
use Proc::ProcessTable;
use DBI;

my $workfile;           # System authentication log file.
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

#-- Check whether process 'remove_firewall_blocking_rule.pl' is running or not. If it is running, abort process. --#
if (firewallRuleRemoverIsRunning()) {
  print "Firewall rules remover is running, process is aborted.\n";
  exit;
}

#-- If another copy of daily_block_attack_ip.pl is running, abort process. --#
if (otherHackerBlockerIsRunning()) {
  print "Another hacker blocking instant is running, process is aborted.\n";
  exit;
}

print "Start Date/Time: " . getCurrentDate(1) . "\n\n";

my $os = (scalar(@ARGV) > 0)? lc(allTrim($ARGV[0])) : '';   # Possible values are 'centos7' and 'ubuntu18'
$workfile = "/var/log/" . (($os eq 'centos7')? 'secure' : 'auth.log');

%reserved_ip = fillReservedIpAddress();

#-- Connect database --#
$dsn = "DBI:mysql:database=$database;host=$host;";
$dbh = DBI->connect($dsn, $user, $pass, {'RaiseError' => 1});

#-- Processing system security log --#
open FILE, "<", $workfile or die("Unable to open the file $workfile \n");
while (<FILE>) {
  my $this_line = $_;
    
  if (attackVectorIsFound($this_line)) {   
    my $this_hacker_ip = getHackerIpAddress($this_line);
    my $this_reserved_ip = $reserved_ip{$this_hacker_ip} + 0;
    
    if (allTrim($this_hacker_ip) ne '' && $this_reserved_ip != 1) {        
      if (!isActiveHackerIpExist($this_hacker_ip)) {
        if (!firewallRuleRemoverIsRunning()) {
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
          #-- If firewall rules remover is running, skip new hacker IP address blocking to avoid firewall rules update racing. --#
          $err_msg .= "Error 3: Since firewall rules remover is running, hacker IP address $this_hacker_ip blocking is skipped.\n";
          $error = 1;
        }
      }    
    }
  }
}
close(FILE);

#-- Processing Nginx log files (if they exist) --#
$workfile = "/var/log/nginx/decoy-access.log";
if (-f $workfile) {
  processWebSiteAttacker($workfile);
}

$workfile = "/var/log/nginx/msg-access.log";
if (-f $workfile) {
  processWebSiteAttacker($workfile);
}

$workfile = "/var/log/nginx/access.log";
if (-f $workfile) {
  processWebSiteAttacker($workfile);
}

if ($cnt > 0) {
  if (!$error) {         # If error is found, don't refresh firewall rules even $cnt > 0.
    my $reload_ok = reloadFirewall();
    
    if ($reload_ok == -1) {
      $err_msg .= "Error 2: Unable to refresh firewall rules, check for it.\n";
      $error = 1;     
    }
    else {
      print "$cnt hacker IP address(es) is/are added.\n";
    }
  }
  else {
    print "Although $cnt hacker IP address(es) is/are added, firewall rules cannot be reloaded due to error is found.\n";
  }
}
else {
  print "No need to refresh firewall\n";
}

$dbh->disconnect;  

if ($error == 1) {
  print "$err_msg \n";
}

print "\nFinish Date/Time: " . getCurrentDate(1) . "\n\n";
#-- End Main Section --#


sub firewallRuleRemoverIsRunning {
  my ($pt, $is_running, $result);
  
  #-- Check whether process 'remove_firewall_blocking_rule.pl' is running or not. If it is running, abort process. --#
  $pt = Proc::ProcessTable->new;
  $is_running = grep {$_->cmndline =~ /remove_firewall_blocking_rule/} @{$pt->table};
  $is_running += 0;
  $result = ($is_running > 0)? 1 : 0;
  
  return $result;  
}


sub otherHackerBlockerIsRunning {
  my ($pt, $run_cnt, $result);

  #-- Check whether other instant of 'daily_block_attack_ip.pl' is running or not. If another instant exists, abort process. --#
  $pt = Proc::ProcessTable->new;
  $run_cnt = grep {$_->cmndline =~ /daily_block_attack_ip/} @{$pt->table};
  $run_cnt += 0;
  $result = ($run_cnt > 2)? 1 : 0;

  return $result;
}


sub fillReservedIpAddress {
  my ($i, $this_ip, %result, @c_class);
  
  $result{'127.0.0.1'} = 1;

  #-- Protect commonly used internal IP addresses. If your internal IP addresses are   --#
  #-- different, add them in here. If it is possible, also include your ISP provided   --*
  #-- external IP address here. However, your external IP address may be changed after --*
  #-- you restart your broadband router.                                               --*
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
  firewall-cmd --quiet --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$hacker_ip' reject"
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


sub webSiteAttackVectorIsFound {
  my ($line) = @_;

  if ($line =~ /function=call_user_func_array/) {
    return 1;
  }

  if ($line =~ /thonkphp/) {
    return 1; 
  }

  if ($line =~ /XDEBUG_SESSION_START=phpstorm/) {
    return 1;
  }

  if ($line =~ /api/ && $line =~ /jsonws/) {
    return 1;
  }

  if ($line =~ /phpunit/) {
    return 1;
  }

  if ($line =~ /phpmyadmin/i && $line =~ /php-my-admin/i) {
    return 1;
  }

  if ($line =~ /b3astmode/i) {
    return 1;
  }

  if ($line =~ /\\x/) {
    return 1;
  }

  if ($line =~ /wget/ && $line =~ /chmod/) {
    return 1;
  }

  return 0;
}


sub processWebSiteAttacker {
  my ($log) = @_;

  open FILE, "<", $log or die("Unable to open the file $log \n");
  while (<FILE>) {
    my $this_line = $_;
    
    if (webSiteAttackVectorIsFound($this_line)) {   
      my $this_hacker_ip = getHackerIpAddress($this_line);
      my $this_reserved_ip = $reserved_ip{$this_hacker_ip} + 0;
    
      if (allTrim($this_hacker_ip) ne '' && $this_reserved_ip != 1) {        
        if (!isActiveHackerIpExist($this_hacker_ip)) {
          if (!firewallRuleRemoverIsRunning()) {
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
              $err_msg .= "Error 1: Unable to add blocking rule of hacker IP address $this_hacker_ip (via website), check for it.\n";
              $error = 1; 
            }
          }
          else {
            #-- If firewall rules remover is running, skip new hacker IP address blocking to avoid firewall rules update racing. --#
            $err_msg .= "Error 3: Since firewall rules remover is running, hacker IP address $this_hacker_ip blocking is skipped.\n";
            $error = 1;
          }
        }    
      }
    }
  }
  close(FILE);
}
