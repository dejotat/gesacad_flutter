-- ============================================================
-- GESACAD - Base de datos
-- Importar en db4free.net o cualquier MySQL 8+
-- ============================================================

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";
SET NAMES utf8mb4;

-- ── USUARIOS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `username` varchar(50) DEFAULT NULL,
  `pass` varchar(50) DEFAULT NULL,
  `rol` enum('Admin','Teacher','Student') DEFAULT NULL,
  `telefono` varchar(30) DEFAULT NULL,
  `bio` text,
  `email_personal` varchar(100) DEFAULT NULL,
  `programa` varchar(100) DEFAULT NULL,
  `semestre` varchar(20) DEFAULT NULL,
  `photo_url` text,
  `email_inst` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `users` VALUES
(6,'Jorge','@Dm1n2026','Admin','3205771845','Administrador GESACAD','dejota0712@gmail.com','Ingenieria de sistemas','Septimo semestre',NULL,'jorgetunubala@unicomfacauca.edu.co'),
(30,'Cristian','Profe2026$','Teacher',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(31,'Eduardo','Profe2026$','Teacher',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(33,'sara','Estu2026$','Student',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(34,'manuel','Estu2026$','Student',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(35,'Felipe','Estu2026$','Student',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(37,'Valeria','Estu2026$','Student',NULL,NULL,NULL,NULL,NULL,NULL,NULL),
(38,'juan','@casa123C','Student',NULL,NULL,NULL,NULL,NULL,NULL,NULL);

ALTER TABLE `users` AUTO_INCREMENT=39;

-- ── CURSOS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `courses` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) DEFAULT NULL,
  `courseCode` varchar(50) DEFAULT NULL,
  `imgCourse` int DEFAULT '1',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `courses` VALUES
(15,'Ingenieria de sistemas','73727',1),
(16,'Aplicaciones moviles','4832',1),
(17,'base de datos','6354',4),
(18,'calidad del software','3535',1),
(19,'programacion','21323',1);

ALTER TABLE `courses` AUTO_INCREMENT=20;

-- ── MATRICULACION ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `registration` (
  `id` int NOT NULL AUTO_INCREMENT,
  `userId` int DEFAULT NULL,
  `courseId` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `registration` VALUES
(93,33,15),(94,35,15),
(95,30,16),(96,35,16),(98,34,16),(99,6,16),
(100,31,17),(101,33,17),(102,35,17),(103,34,17),(105,6,17),
(111,34,18),(112,35,18),(113,38,18),
(114,31,19),(115,34,19),(116,35,19),(117,6,19);

ALTER TABLE `registration` AUTO_INCREMENT=120;

-- ── ACTIVIDADES ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `activities` (
  `id` int NOT NULL AUTO_INCREMENT,
  `week` int DEFAULT NULL,
  `type` varchar(50) DEFAULT NULL,
  `tittle` varchar(200) DEFAULT NULL,
  `description` text,
  `content` text,
  `weighting` decimal(5,2) DEFAULT NULL,
  `startDate` datetime DEFAULT NULL,
  `closingDate` datetime DEFAULT NULL,
  `courseId` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `activities` VALUES
(45,1,'project','entregar proyecto final','adjunto taller','',0.50,'2026-06-02 02:00:00','2026-08-30 23:59:00',16),
(46,1,'midterm','parcial de aplicaciones','parcial unidad 1','',0.25,'2026-06-02 00:00:00','2026-08-30 23:59:00',16),
(47,1,'project','entregar documentacion','taller de calidad','',0.50,'2026-06-03 00:00:00','2026-08-30 23:59:00',18);

ALTER TABLE `activities` AUTO_INCREMENT=50;

-- ── ENTREGAS / CALIFICACIONES ─────────────────────────────────
CREATE TABLE IF NOT EXISTS `resolutionsactivities` (
  `id` int NOT NULL AUTO_INCREMENT,
  `activityId` int DEFAULT NULL,
  `userId` int DEFAULT NULL,
  `courseId` int DEFAULT NULL,
  `resolution` text,
  `dateResolution` datetime DEFAULT NULL,
  `GPA` decimal(3,1) DEFAULT NULL,
  `comment` text,
  `teacherComment` text,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `resolutionsactivities` VALUES
(159,45,35,16,NULL,NULL,3.9,NULL,NULL),
(160,45,34,16,NULL,NULL,NULL,NULL,NULL),
(162,46,35,16,NULL,NULL,NULL,NULL,NULL),
(163,46,34,16,NULL,NULL,NULL,NULL,NULL),
(165,47,34,18,NULL,NULL,NULL,NULL,NULL),
(166,47,35,18,NULL,NULL,NULL,NULL,NULL),
(167,47,38,18,NULL,NULL,NULL,NULL,NULL);

ALTER TABLE `resolutionsactivities` AUTO_INCREMENT=170;

-- ── LOGS (tabla vacia - se llena automaticamente) ─────────────
CREATE TABLE IF NOT EXISTS `system_logs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `accion` varchar(100) NOT NULL,
  `usuario_id` int DEFAULT NULL,
  `detalle` text,
  `fecha` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- FIN
-- ============================================================
