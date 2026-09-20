CREATE TABLE IF NOT EXISTS `shiny_banking_transactions` (
  `id` int NOT NULL AUTO_INCREMENT,
  `receiver_identifier` varchar(64) NOT NULL,
  `receiver_name` varchar(128) NOT NULL,
  `sender_identifier` varchar(64) NOT NULL,
  `sender_name` varchar(128) NOT NULL,
  `value` int NOT NULL,
  `type` varchar(24) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `receiver` (`receiver_identifier`),
  KEY `sender` (`sender_identifier`)
);

CREATE TABLE IF NOT EXISTS `shiny_banking_societies` (
  `society` varchar(64) NOT NULL,
  `society_name` varchar(128) NOT NULL,
  `iban` varchar(16) NOT NULL,
  PRIMARY KEY (`society`),
  UNIQUE KEY `iban` (`iban`)
);