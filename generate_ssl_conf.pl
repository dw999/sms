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
# Program: generate_ssl_conf.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-20      DW              Generate the ssl.conf for Apache web server
#                                               by using user given data in previous step.
# V1.0.01       2019-04-17      DW              - Apache configuration files directory for
#                                                 CentOS 7 is changed from './apache24' to
#                                                 './apache24/centos7'.
#                                               - Handle Apache configuration files for Ubuntu
#                                                 18.04.
# V1.0.02       2019-05-16      DW              Generate Nginx configuration file for CentOS 7.
#                                               Therefore, it needs to handle two command line
#                                               passed parameters: os (operation system) and
#                                               ws (web server). Possible values of os are
#                                               'centos7' and 'ubuntu18', and possible values of
#                                               ws are 'apache' and 'nginx'. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;                    # Defined on sm_webenv.pl

my $template = '';
my $ssl_conf = '';
my $decoy_site_server_name = '';
my $msg_site_server_name = '';
my $ok = 1;
my $msg = '';
my $os = '';                        # Operating system for SMS server.
my $ws = '';                        # Web server will be used by SMS server.

#-- 2019-04-17: Possible values of 'os' are 'centos7' and 'ubuntu18' --#
#-- 2019-05-16: Possible values of 'ws' are 'apache' and 'nginx' --#
foreach my $this_param (@ARGV) {
  my @data = split('=', $this_param);
  if (scalar(@data) >= 2) {
    my $token = lc(allTrim($data[0]));
    my $value = lc(allTrim($data[1]));
    
    if ($token eq 'os') {
      $os = $value;
    }
    elsif ($token eq 'ws') {
      $ws = $value;
    }
  }
}

my $dbh = dbconnect($COOKIE_MSG);   # Defined on sm_db.pl

if ($dbh) {
  ($ok, $msg, $decoy_site_server_name, $msg_site_server_name) = getSitesDomainName($dbh);
  
  if ($ok) {
    if ($os eq 'centos7') {
      if ($ws eq 'apache') {
        $template = './apache24/centos7/httpd_conf/conf.d/ssl.conf.template';
        $ssl_conf = './apache24/centos7/httpd_conf/conf.d/ssl.conf';
      
        open(SSL_CONF, "> $ssl_conf") or die "Unable to create ssl.conf.\n";     
        open(TEMPLATE, "< $template") or die "Unable to open ssl.conf template.\n";
        while (<TEMPLATE>) {
          my $this_line = $_;
      
          if ($this_line =~ /{decoy_site_server_name}/) {
            $this_line =~ s/{decoy_site_server_name}/$decoy_site_server_name/g;
          }
          elsif ($this_line =~ /{msg_site_server_name}/) {
            $this_line =~ s/{msg_site_server_name}/$msg_site_server_name/g;
          }
      
          print SSL_CONF $this_line;
        }
   
        close(TEMPLATE);
        close(SSL_CONF);
      }
      elsif ($ws eq 'nginx') {
        $template = './nginx/centos7/nginx.conf.template';
        $ssl_conf = './nginx/centos7/nginx.conf';
      
        open(SSL_CONF, "> $ssl_conf") or die "Unable to create nginx.conf.\n";     
        open(TEMPLATE, "< $template") or die "Unable to open nginx.conf template.\n";
        while (<TEMPLATE>) {
          my $this_line = $_;
      
          if ($this_line =~ /{decoy_site_server_name}/) {
            $this_line =~ s/{decoy_site_server_name}/$decoy_site_server_name/g;
          }
          elsif ($this_line =~ /{msg_site_server_name}/) {
            $this_line =~ s/{msg_site_server_name}/$msg_site_server_name/g;
          }
      
          print SSL_CONF $this_line;
        }
   
        close(TEMPLATE);
        close(SSL_CONF);        
      }
      else {
        print "Error: Invalid web server option is given or missing for CentOS 7.\n";  
      }
    }
    elsif ($os eq 'ubuntu18') {
      if ($ws eq 'apache') {
        #-- Step 1: Generate decoy site SSL virtual host configuration file --#
        $template = './apache24/ubuntu18/httpd_conf/sites-available/ssl-decoy-site.conf.template';
        $ssl_conf = './apache24/ubuntu18/httpd_conf/sites-available/ssl-decoy-site.conf';
      
        open(SSL_CONF, "> $ssl_conf") or die "Unable to create decoy site ssl-decoy-site.conf.\n";     
        open(TEMPLATE, "< $template") or die "Unable to open decoy site ssl-decoy-site.conf template.\n";
        while (<TEMPLATE>) {
          my $this_line = $_;
      
          if ($this_line =~ /{decoy_site_server_name}/) {
            $this_line =~ s/{decoy_site_server_name}/$decoy_site_server_name/g;
          }
      
          print SSL_CONF $this_line;
        }
   
        close(TEMPLATE);
        close(SSL_CONF);
      
        #-- Step 2: Generate messaging site SSL virtual host configuration file --#
        $template = './apache24/ubuntu18/httpd_conf/sites-available/ssl-message-site.conf.template';
        $ssl_conf = './apache24/ubuntu18/httpd_conf/sites-available/ssl-message-site.conf';
      
        open(SSL_CONF, "> $ssl_conf") or die "Unable to create messaging site ssl-message-site.conf.\n";     
        open(TEMPLATE, "< $template") or die "Unable to open messaging site ssl-message-site.conf template.\n";
        while (<TEMPLATE>) {
          my $this_line = $_;
      
          if ($this_line =~ /{msg_site_server_name}/) {
            $this_line =~ s/{msg_site_server_name}/$msg_site_server_name/g;
          }
        
          print SSL_CONF $this_line;
        }
   
        close(TEMPLATE);
        close(SSL_CONF);
      }
      else {
        print "Error: Invalid web server option is given or missing for Debian 9 or Ubuntu 18.\n";
      }
    }
    else {
      print "Error: Invalid platform is given or missing.\n";
    }
  }
  else {
    print "Unable to get sites domain name. Error: $msg\n";
  }
}
else {
  print "Error: Unable to connect to msgdb, Web server configuration file generation failure.\n";
}

dbclose($dbh);
#-- End Main Section --#


sub getSitesDomainName {
  my ($dbh) = @_;
  my ($ok, $msg, $sql, $sth, $decoy_site_server_name, $msg_site_server_name);
  
  $ok = 1;
  $msg = '';
  
  $sql = <<__SQL;
  SELECT site_type, site_dns
    FROM sites
    WHERE status = 'A'
__SQL
  
  $sth = $dbh->prepare($sql);
  if ($sth->execute()) {
    while (my @data = $sth->fetchrow_array()) {
      my $site_type = uc($data[0]);
      my $site_dns = allTrim($data[1]);
      $site_dns =~ s/https:\/\///g;
      
      if ($site_type eq 'DECOY') {
        $decoy_site_server_name = $site_dns;
      }
      elsif ($site_type eq 'MESSAGE') {
        $msg_site_server_name = $site_dns;
      }
    }
  }
  else {
    $msg = $sth->errstr;
    $ok = 0;
  }
  $sth->finish;

  return ($ok, $msg, $decoy_site_server_name, $msg_site_server_name);
}

