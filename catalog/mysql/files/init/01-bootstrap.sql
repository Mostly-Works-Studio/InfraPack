-- Runs once, only when the mysql-data volume is empty.
-- Add your own .sql files in this directory; they run in alphabetical order.

CREATE DATABASE IF NOT EXISTS `local`
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Give the dev user full rights on everything (local only).
GRANT ALL PRIVILEGES ON *.* TO 'dev'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
