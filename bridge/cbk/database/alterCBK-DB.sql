ALTER TABLE `owned_vehicles`
    ADD COLUMN IF NOT EXISTS `stolen` INT(1) DEFAULT '0';
