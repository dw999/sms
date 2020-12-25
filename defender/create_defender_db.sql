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
-- V1.0.00       2018-12-22      DW              Create database for CentOS/RedHat 7 defender.
-- V1.0.01       2019-05-24      DW              Define indexes for database table.
-- V1.0.02       2020-12-25      DW              Change data type of hacker_ip.hit_date to 'datetime'.
--
-- Remark: It is part of SMS installation program.
-----------------------------------------------------------------------------------------------------

DROP DATABASE IF EXISTS defendb;

CREATE DATABASE defendb
  DEFAULT CHARACTER SET utf8
  DEFAULT COLLATE utf8_general_ci;

GRANT ALL ON defendb.* TO 'secure'@localhost IDENTIFIED BY 'Txf742kp4M';

USE defendb;


CREATE TABLE `hacker_ip` (
  `ipv4_address` varchar(20) DEFAULT NULL,
  `ipv6_address` varchar(255) DEFAULT NULL,
  `hit_date` datetime DEFAULT NULL,
  `is_active` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX idx_ipv4 ON hacker_ip(ipv4_address);
CREATE INDEX idx_hit_date_is_active ON hacker_ip(hit_date, is_active);
