-- phpMyAdmin SQL Dump
-- version 5.2.0
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 06-12-2023 a las 05:20:13
-- Versión del servidor: 10.4.27-MariaDB
-- Versión de PHP: 8.2.0

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `bdgesacad`
--

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `activities`
--

CREATE TABLE `activities` (
  `id` int(50) NOT NULL,
  `tittle` varchar(50) NOT NULL,
  `week` int(2) NOT NULL,
  `type` enum('midterm','project','resource','other') NOT NULL,
  `description` varchar(2000) NOT NULL,
  `content` text DEFAULT NULL,
  `weighting` decimal(3,2) NOT NULL DEFAULT 0.00,
  `startDate` datetime NOT NULL,
  `closingDate` datetime NOT NULL,
  `courseId` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `activities`
--

INSERT INTO `activities` (`id`, `tittle`, `week`, `type`, `description`, `content`, `weighting`, `startDate`, `closingDate`, `courseId`) VALUES
(151, 'Parcial 1', 1, 'midterm', 'sdauhdshishjas', '', '0.20', '2023-12-05 21:19:00', '2023-12-13 21:19:00', 155),
(152, 'sad', 1, 'midterm', 'asd', '', '0.00', '2023-12-05 22:34:00', '2023-12-13 22:34:00', 155);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `courses`
--

CREATE TABLE `courses` (
  `id` int(11) NOT NULL,
  `name` varchar(50) DEFAULT NULL,
  `courseCode` varchar(50) DEFAULT NULL,
  `imgCourse` int(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `courses`
--

INSERT INTO `courses` (`id`, `name`, `courseCode`, `imgCourse`) VALUES
(1, 'Calculo 2', '10985M', 1),
(2, 'Arquitectura 1', '10000M', 2),
(3, 'Sistemas Operativos', '52951N', 3),
(155, 'asd', '217983217M', 2);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `registration`
--

CREATE TABLE `registration` (
  `userId` int(11) NOT NULL,
  `courseId` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `registration`
--

INSERT INTO `registration` (`userId`, `courseId`) VALUES
(1, 1),
(1, 2),
(1, 3),
(2, 155),
(3, 155),
(4, 155);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `resolutionsactivities`
--

CREATE TABLE `resolutionsactivities` (
  `id` int(11) NOT NULL,
  `activityId` int(11) DEFAULT NULL,
  `userId` int(11) DEFAULT NULL,
  `resolution` text DEFAULT NULL,
  `dateResolution` datetime DEFAULT NULL,
  `GPA` decimal(3,2) DEFAULT NULL,
  `courseId` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `resolutionsactivities`
--

INSERT INTO `resolutionsactivities` (`id`, `activityId`, `userId`, `resolution`, `dateResolution`, `GPA`, `courseId`) VALUES
(123, 151, 3, NULL, NULL, '5.00', 155),
(124, 151, 4, NULL, NULL, '3.00', 155),
(125, 152, 3, NULL, NULL, NULL, 155),
(126, 152, 4, NULL, NULL, NULL, 155);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(50) DEFAULT NULL,
  `pass` varchar(50) DEFAULT NULL,
  `rol` enum('Admin','Teacher','Student') DEFAULT 'Student'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `users`
--

INSERT INTO `users` (`id`, `username`, `pass`, `rol`) VALUES
(1, 'RedRum237', '12345', 'Admin'),
(2, 'Tilin', '54321', 'Teacher'),
(3, 'Vergelio', '55555', 'Student'),
(4, 'asd', 'asd', 'Student');

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `activities`
--
ALTER TABLE `activities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idCourse` (`courseId`);

--
-- Indices de la tabla `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`),
  ADD UNIQUE KEY `courseCode` (`courseCode`);

--
-- Indices de la tabla `registration`
--
ALTER TABLE `registration`
  ADD PRIMARY KEY (`userId`,`courseId`),
  ADD KEY `courseId` (`courseId`);

--
-- Indices de la tabla `resolutionsactivities`
--
ALTER TABLE `resolutionsactivities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `activityId` (`activityId`),
  ADD KEY `userId` (`userId`),
  ADD KEY `courseIdForeignKey` (`courseId`);

--
-- Indices de la tabla `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `activities`
--
ALTER TABLE `activities`
  MODIFY `id` int(50) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=153;

--
-- AUTO_INCREMENT de la tabla `courses`
--
ALTER TABLE `courses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=156;

--
-- AUTO_INCREMENT de la tabla `resolutionsactivities`
--
ALTER TABLE `resolutionsactivities`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=127;

--
-- AUTO_INCREMENT de la tabla `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `activities`
--
ALTER TABLE `activities`
  ADD CONSTRAINT `activities_ibfk_1` FOREIGN KEY (`courseId`) REFERENCES `courses` (`id`);

--
-- Filtros para la tabla `registration`
--
ALTER TABLE `registration`
  ADD CONSTRAINT `registration_ibfk_1` FOREIGN KEY (`userId`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `registration_ibfk_2` FOREIGN KEY (`courseId`) REFERENCES `courses` (`id`);

--
-- Filtros para la tabla `resolutionsactivities`
--
ALTER TABLE `resolutionsactivities`
  ADD CONSTRAINT `courseIdForeignKey` FOREIGN KEY (`courseId`) REFERENCES `courses` (`id`),
  ADD CONSTRAINT `resolutionsactivities_ibfk_1` FOREIGN KEY (`activityId`) REFERENCES `activities` (`id`),
  ADD CONSTRAINT `resolutionsactivities_ibfk_2` FOREIGN KEY (`userId`) REFERENCES `users` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
