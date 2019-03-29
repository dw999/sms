-----------------------------------------------------------------------------------------------------
-- Name: create_db.sql
--
-- Ver           Date            Author          Comment
-- =======       ===========     ===========     ==========================================
-- V1.0.00       2018-12-22      DW              Create database for CentOS/RedHat 7 defender.
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
  `hit_date` date DEFAULT NULL,
  `is_active` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


