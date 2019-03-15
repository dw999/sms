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
# Program: /www/pdatools/cgi-pl/user/add_user.pl
#
# Ver           Date            Author          Comment
# =======       ===========     ===========     ==========================================
# V1.0.00       2018-06-05      AY              Let new user finalize registration process
#                                               and create his/her account.
# V1.0.01       2018-07-27      AY              With suggestions from the team, the remark 
#                                               3 is amended.
# V1.0.02       2018-08-21      AY              Make 'alias' compulsory.
# V1.0.03       2018-12-08      AY              Rewrite this function to use jQuery Mobile.
# V1.0.04       2018-12-10      AY              With unknown reason, long escaped URI data
#                                               let jQuery Mobile library raise error. So,
#                                               this program is amended to work-around this
#                                               issue.
# V1.0.05       2019-01-14      AY              Add transient status 'S' for selected applicant
#                                               to ensure correct token must be given, before
#                                               he/she can go to next step 'input_user_data.pl'.
##########################################################################################

push @INC, '/www/perl_lib';

use strict;
use URI::Escape;
use CGI qw/:standard/;
require "sm_webenv.pl";
require "sm_db.pl";
require "sm_user.pl";

our $COOKIE_MSG;                                      # Defined on sm_webenv.pl

my $token = allTrim(uri_escape(paramAntiXSS('tk')));  # Authentication token. Note: Perl CGI parameters receiving function unescape passed data automatically.
my $user = allTrim(paramAntiXSS('user'));             # Username for the applicant.

printFreeHeader('Create Account');                    # Defined on sm_webenv.pl

my $dbh = dbconnect($COOKIE_MSG);
my ($ok, $msg, $apply_id);

($ok, $msg, $apply_id) = loadApplicantInfo($dbh, $token);  

if ($ok) {
  redirectTo("/cgi-pl/user/input_user_data.pl?apply_id=$apply_id&user=$user");
}
else {
  alert($msg);
  redirectTo("/cgi-pl/index.pl");
}

dbclose($dbh);
#-- End Main Section --#


sub loadApplicantInfo {
  my ($dbh, $token) = @_;
  my ($sql, $sth, $ok, $msg, $apply_id, $name, $email, $apply_date, $status);
  
  $ok = 1;
  $msg = $name = $email = '';
  $apply_id = 0;
  
  if ($dbh) {
    $sql = <<__SQL;
    SELECT apply_id, name, email, apply_date, status
      FROM applicant
      WHERE token = ?
__SQL

    $sth = $dbh->prepare($sql);
    if ($sth->execute($token)) {
      ($apply_id, $name, $email, $apply_date, $status) = $sth->fetchrow_array();
      
      if ($apply_id <= 0) {
        $msg = "Unable to find your apply record";
        $ok = 0;
      }
      
      if ($ok && $status ne 'A') {
        if ($status eq 'C') {
          #-- Alert applicant that his/her registration acceptance link may have been intercepted and used by someone --#
          $msg = "You have already created your account. If you don't know it, something is wrong, please contact your referrer ASAP!";          
        }
        elsif ($status eq 'T') {
          $msg = "Your application has already expired, please apply again.";
        }
        elsif ($status eq 'S') {
          $msg = "Someone is creating your user account. If it is not you, please contact your referrer at once.";
        }
        else {
          #-- It may be system problem or hacking activity. Registration record with status not in 'A', 'C' or 'T' should not be here. --#
          $msg = "With unknown reason, registration process is failure.";
        }
        
        $ok = 0;
      }      
    }
    else {
      $msg = "System issue is found, please try again later. Error: " . $sth->errstr;
      $ok = 0;
    }
    $sth->finish;
    
    #-- Check whether approval period has been passed --#
    if ($ok) {
      if (_isTimeLimitPassed($dbh, $apply_date, '7 00:00:00')) {      # Note: 1. '7 00:00:00' means 7 days, 2. It is defined on sm_user.pl
        setApplicantStatus($dbh, $apply_id, 'T');      # Timeout.
        $msg = "You are too late to finalize your registration, valid period has been passed. Please apply again.";
        $ok = 0;
      }      
    }    
  }
  else {
    $msg = "Invalid database connection handler is found, process cannot proceed.";
    $ok = 0;
  }
  
  #-- If everything is OK, turn applicant status to 'S' temporary, in order to avoid hackers to --#
  #-- bypass token given. Note: Current applicant status is 'A', it needs to change it to 'S'   --#
  #-- temporary.                                                                                --#
  if ($ok) {
    ($ok, $msg) = setApplicantStatus($dbh, $apply_id, 'S');               # Defined on sm_user.pl
  }
  
  return ($ok, $msg, $apply_id);  
}

