CREATE TABLE IF NOT EXISTS `nd_mdt_weapons` (
	`character` VARCHAR(12) DEFAULT NULL,
	`weapon` VARCHAR(50) DEFAULT NULL,
	`serial` VARCHAR(50) DEFAULT NULL,
	`owner_name` VARCHAR(100) DEFAULT NULL,
	`stolen` INT(1) DEFAULT '0'
);
