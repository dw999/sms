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
# Program: /www/perl_lib/sm_db.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-05-24      AY              Library functions used for database operations.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use DBI;
require "sm_webenv.pl";

our $COOKIE_PDA;                                      # Both are defined on sm_webenv.pl
our $COOKIE_MSG;                                  

sub dbconnect {
  my ($what_cookie) = @_;
  my ($database, $host, $user, $pass, $dsn, $dbh, $sth, %attr);
  
  %attr = (
    AutoCommit => 1,          
    PrintError => 0,
    RaiseError => 0,           # Don't raise exception but just return error message as error occur.
  );
        
  if ($what_cookie eq $COOKIE_PDA) {
    $database = 'pdadb';
    $host = 'localhost';
    $user = 'pdadmin';
    $pass = 'Yt83344Keqpkgw34';
    $dsn = "DBI:mysql:database=$database;host=$host;";
    $dbh = DBI->connect($dsn, $user, $pass, \%attr);
    $sth = $dbh->prepare("use $database");
    $sth->execute();
    $sth->finish();        
  }
  elsif ($what_cookie eq $COOKIE_MSG) {
    $database = 'msgdb';
    $host = 'localhost';
    $user = 'msgadmin';
    $pass = 'cPx634BzAr1338Ux';
    $dsn = "DBI:mysql:database=$database;host=$host;";
    $dbh = DBI->connect($dsn, $user, $pass, \%attr);
    $sth = $dbh->prepare("use $database");
    $sth->execute();
    $sth->finish();            
  }
  else {
    $dbh = undef;
  }
  
  #-- Set the maximum length of fetch data, and 65536 is the maximum length of MySQL 'text' data type. --#
  #-- For more information, see http://search.cpan.org/~timb/DBI/DBI.pm#LongReadLen                    --#
  $dbh->{LongReadLen} = 65536;
  
  return $dbh;  
}


sub dbclose {
  my ($dbh) = @_;
  
  if ($dbh) {
    $dbh->disconnect;
  }
}


sub startTransaction {
  my ($dbh) = @_;
  my ($rc, $result);
  
  if ($dbh) {    
    $rc = $dbh->begin_work();
    if ($dbh->{AutoCommit} == 0) {
      $result = 1;
    }
    else {
      $result = 0;
    }    
  }
  else {
    $result = 0;
  }
  
  return $result;
}


sub commitTransaction {
  my ($dbh) = @_;
  
  if ($dbh) {
    $dbh->commit;
    $dbh->{AutoCommit} = 1;
  }  
}


sub rollbackTransaction {
  my ($dbh) = @_;
  
  if ($dbh) {
    $dbh->rollback;
    $dbh->{AutoCommit} = 1;
  }  
}


1;