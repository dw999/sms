#!/usr/bin/perl

##########################################################################################
# Program: generate_ssl_conf.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-12-20      DW              Generate the ssl.conf for Apache web server
#                                               by using user given data in previous step. 
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
require "sm_webenv.pl";
require "sm_db.pl";

our $COOKIE_MSG;                    # Defined on sm_webenv.pl

my $template = './apache24/httpd_conf/conf.d/ssl.conf.template';
my $ssl_conf = './apache24/httpd_conf/conf.d/ssl.conf';
my $decoy_site_server_name = '';
my $msg_site_server_name = '';
my $ok = 1;
my $msg = '';

my $dbh = dbconnect($COOKIE_MSG);   # Defined on sm_db.pl

if ($dbh) {
  ($ok, $msg, $decoy_site_server_name, $msg_site_server_name) = getSitesDomainName($dbh);
  
  if ($ok) {
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
  else {
    print "Unable to get sites domain name. Error: $msg\n";
  }
}
else {
  print "Error: Unable to connect to msgdb, Apache server configuration file generation failure.\n";
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

