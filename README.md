# MySQL database backup

A bash script to store databases in separate files with daily, weekly and monthly rotation.

## Usage

`./mysqlbackup.sh`

## Configuration (optional)

Copy `mysqlbackup.sample.conf` to: `mysqlbackup.conf` and customise as necessary.

On MariaDB systems where `mysql` and `mysqldump` show deprecation warnings, set:

```
DB_CLIENT="mariadb"
```

This makes the script use `mariadb` and `mariadb-dump` by default. You can still
set `MYSQL` and `MYSQLDUMP` directly if you need custom command paths.

Backups can be transferred to a remote server with FTP or SFTP. To use SFTP,
set `SFTP="y"` and configure `SFTPHOST`, `SFTPUSER`, `SFTPPASS`, `SFTPPORT`,
`SFTPKEY`, and `SFTPDIR` in `mysqlbackup.conf`.

For password authentication, set `SFTPPASS` and leave `SFTPKEY` empty. This
requires `sshpass` on the machine running the backup. For key authentication,
set `SFTPKEY` and leave `SFTPPASS` empty.

## Background

Normally using:
```
mysqldump --all-databases
```

Means that all databases are backed up into one massive single file; so it makes it a little bit tricky to pull out individual databases.

This is based on [MySQL backup bash script](http://www.ameir.net/blog/index.php?/archives/18-MySQL-Backup-to-FTP-and-Email-Shell-Script-for-Cron-v2.1.html) will automatically separate out the databases into their own files making it a lot easier to manage.

The `mysqldump` command has been customised to be more reliable (handling UTF-8, stored procedures, not breaking foreign key indexes etc.) and the ability to handle multiple config files. It can also automatically rotate archive backups for `x` number of months, weeks and days.
