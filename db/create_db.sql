----
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
----

-----------------------------------------------------------------------------------------------------
-- Name: create_db.sql
--
-- Ver           Date            Author          Comment
-- =======       ===========     ===========     ==========================================
-- V1.0.00       2018-12-12      DW              Create databases for SMS, and put in essential data.
-- V1.0.01       2019-05-24      DW              Define indexes for all database tables.
--
-- Remark: It is part of SMS installation program.
-----------------------------------------------------------------------------------------------------

DROP DATABASE IF EXISTS msgdb;

CREATE DATABASE msgdb
  DEFAULT CHARACTER SET utf8
  DEFAULT COLLATE utf8_general_ci;

GRANT ALL ON msgdb.* TO 'msgadmin'@localhost IDENTIFIED BY 'cPx634BzAr1338Ux';

USE msgdb;

CREATE TABLE user_list
(
  user_id bigint unsigned not null auto_increment,
  user_name varchar(64),
  user_alias varchar(256),
  name varchar(256),
  happy_passwd varchar(256),
  unhappy_passwd varchar(256),
  login_failed_cnt int,
  user_role int,
  email varchar(256),
  tg_id varchar(128),
  refer_by bigint,
  join_date date,
  status varchar(6),
  cracked int,
  cracked_date datetime,
  inform_new_msg int,
  PRIMARY KEY (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_name ON user_list(user_name);
CREATE INDEX idx_usr_role_status ON user_list(user_role, status);

LOCK TABLES `user_list` WRITE;
ALTER TABLE `user_list` DISABLE KEYS;
INSERT INTO `user_list` VALUES (1,'smsadmin','SA','','$2a$15$qfpF3w5GxjRkLg8B04OWY.7DstPc.05MdC.O3ZmDJ.NlhuIREkmNm','$2a$15$nYiz.sdZ9towP.w8hdCax.qLLt2qkh2D5Cdr0UPUaxkumuT2DzkRO',0,2,'your_email_address','',0,current_date(),'A',0,null,1);
ALTER TABLE `user_list` ENABLE KEYS;
UNLOCK TABLES;

CREATE TABLE tg_bot_profile
(
  bot_name varchar(128),
  bot_username varchar(128),
  http_api_token varchar(256)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE applicant
(
  apply_id bigint unsigned not null auto_increment,
  name varchar(256),
  email varchar(256),
  refer_email varchar(256),
  remark varchar(1024),
  apply_date datetime,
  status varchar(6),
  seed varchar(256),
  token varchar(512),  
  PRIMARY KEY (apply_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Note: 'token' in UTF-8 is too long to be used as primary key.
CREATE TABLE login_token_queue
(
  token varchar(512) not null,
  token_addtime datetime,
  token_usetime datetime,
  token_seed varchar(256),
  status varchar(6),
  user_id bigint
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_token ON login_token_queue(token);

CREATE TABLE web_session
(
  sess_code varchar(128),
  user_id bigint,
  sess_until datetime,
  ip_address varchar(256),
  http_user_agent varchar(384),
  secure_key varchar(128),
  status varchar(2),
  PRIMARY KEY (sess_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id ON web_session(user_id);

CREATE TABLE hack_history
(
  ipv4_addr varchar(20),
  user_id bigint,
  first_hack_time datetime,
  last_hack_time datetime,
  hack_cnt int,
  ip_blocked int 
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id_ipv4 ON hack_history(user_id, ipv4_addr); 

CREATE TABLE msg_group
(
  group_id bigint unsigned not null auto_increment,
  group_name varchar(256),
  group_type int,
  msg_auto_delete int,
  delete_after_read int,
  encrypt_key varchar(256),
  status varchar(6),
  refresh_token varchar(16),
  PRIMARY KEY (group_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE group_member
(
  group_id bigint unsigned,
  user_id bigint,
  group_role varchar(1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_grp_id_usr_id ON group_member(group_id, user_id);
CREATE INDEX idx_grp_id ON group_member(group_id);

CREATE TABLE message
(
  msg_id bigint unsigned not null auto_increment,
  group_id bigint unsigned,
  sender_id bigint,
  send_time datetime,  
  send_status varchar(6),  
  msg text,
  fileloc varchar(512),
  op_flag varchar(1),
  op_user_id bigint,
  op_msg text,  
  PRIMARY KEY (msg_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_grp_id_msg_id ON message(group_id, msg_id);

CREATE TABLE msg_tx
(
  msg_id bigint unsigned,
  receiver_id bigint,
  read_status varchar(6),
  read_time datetime,
  PRIMARY KEY (msg_id, receiver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_msg_id ON msg_tx(msg_id);
CREATE INDEX idx_rev_id_msg_id ON msg_tx(receiver_id, msg_id);

CREATE TABLE new_msg_inform
(
  user_id bigint unsigned,
  period datetime,
  status varchar(2),
  try_cnt int
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id_status ON new_msg_inform(user_id, status); 

CREATE TABLE unhappy_login_history
(
  log_id bigint unsigned not null auto_increment,
  user_id bigint unsigned,
  login_time datetime,
  loc_longitude numeric(13,6),
  loc_latitude numeric(13,6),
  browser_signature varchar(512),
  PRIMARY KEY (log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id ON unhappy_login_history(user_id);

CREATE TABLE decoy_sites
(
  site_url varchar(512),
  key_words varchar(512)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `decoy_sites` WRITE;
INSERT INTO `decoy_sites` VALUES ('https://nexter.org','News'),('https://techcrunch.com','Tech News'),('https://thenextweb.com','Tech News'),('https://www.wired.com','Tech News'),('https://www.firstpost.com/tech','Tech News'),('https://gizmodo.com','Tech News'),('https://mashable.com','Tech News'),('https://www.theverge.com','Tech News'),('https://www.digitaltrends.com','Tech News'),('https://www.techradar.com','Tech News'),('https://www.macrumors.com','Tech News'),('https://www.codeproject.com','Programming Forum'),('https://stackoverflow.com','Programming Forum'),('https://forum.xda-developers.com','Programming Forum'),('https://bytes.com','Programming Forum'),('https://www.webhostingtalk.com','Forum'),('https://thehackernews.com','IT security news'),('https://www.infosecurity-magazine.com','IT security news'),('https://www.csoonline.com','IT security news'),('https://www.tripwire.com/state-of-security','IT security news'),('https://www.troyhunt.com','IT security blog'),('https://www.lastwatchdog.com','IT security watch'),('https://www.schneier.com','IT security watch'),('https://blogs.akamai.com','IT security blog'),('https://krebsonsecurity.com','IT security news'),('https://taosecurity.blogspot.com/?m=1','IT security blog'),('https://www.pcworld.com','IT news'),('https://www.welivesecurity.com','IT security news'),('https://www.afcea.org/content','IT security news'),('https://threatpost.com','IT security news'),('https://www.computerworld.com/category/emerging-technology','IT news'),('https://www.grahamcluley.com','IT security news'),('https://www.itsecurityguru.org','IT security news');
UNLOCK TABLES;

CREATE TABLE sys_error_log
(
  log_id bigint unsigned not null auto_increment,
  user_id bigint unsigned,
  brief_err_msg varchar(256),
  detail_err_msg varchar(1024),
  log_time datetime,
  browser_signature varchar(512),
  PRIMARY KEY (log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE sys_email_sender
(
  ms_id bigint not null auto_increment,
  email varchar(128),
  m_user varchar(64),
  m_pass varchar(64),
  smtp_server varchar(128),
  port int,
  status varchar(1),
  PRIMARY KEY (ms_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE sites
(
  site_type varchar(10),
  site_dns varchar(128),
  status varchar(1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `sites` WRITE;
INSERT INTO `sites` VALUES ('DECOY','https://decoy.site.com','A'),('MESSAGE','https://messaging.site.net','A');
UNLOCK TABLES;

CREATE TABLE file_type
(
  ftype_id bigint not null auto_increment,
  file_ext varchar(16),
  file_type varchar(64),
  PRIMARY KEY (ftype_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `file_type` WRITE;
ALTER TABLE `file_type` DISABLE KEYS;
INSERT INTO `file_type` VALUES (1,'jpg','image'),(2,'jpeg','image'),(3,'png','image'),(4,'gif','image'),(5,'bmp','image'),(6,'tif','image'),(7,'tiff','image'),(8,'mp3','audio/mpeg'),(9,'ogg','audio/ogg'),(10,'wav','audio/wav'),(11,'mp4','video/mp4'),(12,'webm','video/webm'),(13,'amr','aud_convertable'),(14,'3gpp','aud_convertable');
ALTER TABLE `file_type` ENABLE KEYS;
UNLOCK TABLES;

CREATE TABLE sys_settings
(
  sys_key varchar(64) not null,
  sys_value varchar(512),
  PRIMARY KEY (sys_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `sys_settings` WRITE;
INSERT INTO `sys_settings` VALUES ('audio_converter',"/usr/bin/ffmpeg -i '{input_file}' '{output_file}'"),('connection_mode','0'),('decoy_company_name','PDA Tools'),('msg_block_size','30'),('session_period','02:00:00'),('old_msg_delete_days','14');
UNLOCK TABLES;


DROP DATABASE IF EXISTS pdadb;

CREATE DATABASE pdadb
  DEFAULT CHARACTER SET utf8
  DEFAULT COLLATE utf8_general_ci;

GRANT ALL ON pdadb.* TO 'pdadmin'@localhost IDENTIFIED BY 'Yt83344Keqpkgw34';

USE pdadb;

CREATE TABLE web_session
(
  sess_code varchar(128),
  user_id bigint,
  sess_until datetime,
  ip_address varchar(256),
  http_user_agent varchar(384),
  secure_key varchar(128),
  status varchar(2),
  PRIMARY KEY (sess_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id ON web_session(user_id);

CREATE TABLE feature_store
(
  feature_id bigint unsigned not null auto_increment,
  feature_url varchar(512),
  feature_icon varchar(256),
  PRIMARY KEY (feature_id)  
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `feature_store` WRITE;
ALTER TABLE `feature_store` DISABLE KEYS;
INSERT INTO `feature_store` VALUES (1,'/cgi-pl/tools/notes.pl','/images/notes.png'),(2,'/cgi-pl/tools/scheduler.pl','/images/scheduler.png');
ALTER TABLE `feature_store` ENABLE KEYS;
UNLOCK TABLES;

CREATE TABLE feature_list
(
  feature_id bigint,
  list_order int
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `feature_list` WRITE;
INSERT INTO `feature_list` VALUES (1,1),(2,2);
UNLOCK TABLES;

CREATE TABLE schedule_event
(
  event_id bigint unsigned not null auto_increment,
  user_id bigint,
  event_title varchar(256),
  event_detail text,
  ev_start datetime,
  ev_end datetime,
  PRIMARY KEY (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_usr_id_ev_start ON schedule_event(user_id, ev_start); 

CREATE TABLE schedule_reminder
(
  reminder_id bigint unsigned not null auto_increment,
  event_id bigint,
  remind_before varchar(32),
  remind_unit varchar(16),
  has_informed int,
  PRIMARY KEY (reminder_id) 
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE notes
(
  notes_id bigint unsigned not null auto_increment,
  user_id bigint unsigned,
  notes_title varchar(256),
  notes_content text,
  create_date datetime,
  update_date datetime,  
  PRIMARY KEY (notes_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



