#!/usr/bin/env bash

# MySQL database backup (databases in separate files) with daily, weekly and monthly rotation
# v0.0.5

# Sebastian Flippence (http://seb.flippence.uk) originally based on code from: Ameir Abdeldayem (http://www.ameir.net)
# You are free to modify and distribute this code,
# so long as you keep the authors name and URL in it.

# By default it will search for the config file in the same directory as this script, otherwise you can choose it (e.g. ./mysqlbackup.sh /path/to/mysqlbackup.conf)

# Read the config file
if [ "$1" = "" ]; then
	CONFIG_FILE="`dirname $0`/mysqlbackup.conf"
else
	CONFIG_FILE="$1"
fi

if [ -f "$CONFIG_FILE" ]; then
	echo "Loading config file ($CONFIG_FILE)"
	. $CONFIG_FILE
else
	echo "Config file not found ($CONFIG_FILE)"
	exit 1
fi

# Setup some command defaults (can be overriden by the config)
MYSQL=${MYSQL:-`which mysql`}
MYSQLDUMP=${MYSQLDUMP:-`which mysqldump`}

# Date format that is appended to filename
DATE=`date +'%Y-%m-%d'`

# Setup paths
ARCHIVE_PATH="${BACKDIR}/${ARCHIVE_PATH}"
CURRENT_BACKDIR="${BACKDIR}/${LATEST_PATH}/${DATE}"
MYSQL_LOGS="${BACKDIR}/logs/mysql"

function checkMysqlUp() {
	$MYSQL -N -h $HOST --user=$USER --password=$PASS -e status
}
trap checkMysqlUp 0

function error() {
  local PARENT_LINENO="$1"
  local MESSAGE="$2"
  local CODE="${3:-1}"
  if [[ -n "$MESSAGE" ]] ; then
    echo "Error on or near line ${PARENT_LINENO}: ${MESSAGE}; exiting with status ${CODE}"
  else
    echo "Error on or near line ${PARENT_LINENO}; exiting with status ${CODE}"
  fi
  exit "${CODE}"
}
trap 'error ${LINENO}' ERR

# Check backup directory exists
# if not, create it
if  [ -e $CURRENT_BACKDIR ]; then
	echo "Backup directory exists (${CURRENT_BACKDIR})"
else
	mkdir -p $CURRENT_BACKDIR
	echo "Created backup directory (${CURRENT_BACKDIR})"
fi

if  [ ! -e $MYSQL_LOGS ]; then
	mkdir -p $MYSQL_LOGS
fi

if  [ $DUMPALL = "y" ]; then
	echo "Creating list of databases on: ${HOST}..."

	$MYSQL -N -h $HOST --user=$USER --password=$PASS -e "show databases;" > ${CURRENT_BACKDIR}/dbs_on_${SERVER}.txt

	# redefine list of databases to be backed up
	DBS=`sed -e ':a;N;$!ba;s/\n/ /g' -e 's/Database //g' ${CURRENT_BACKDIR}/dbs_on_${SERVER}.txt`
fi

echo "Backing up MySQL databases..."

for database in $DBS; do
	echo "${database}..."

	if [ $database = "information_schema" ] || [ $database = "mysql" ] || [ $database = "performance_schema" ] || [ $database = "sys" ]; then
		echo "Skipping ${database}..."
		continue
	fi

	$MYSQLDUMP --host=$HOST --user=$USER --password=$PASS --opt --default-character-set=utf8 --routines --allow-keywords --dump-date $database --result-file=${CURRENT_BACKDIR}/${SERVER}-MySQL-backup-$database-${DATE}.sql --log-error=${MYSQL_LOGS}/${SERVER}-MySQL-backup-$database-error.log

	tar --remove-files -czvf ${CURRENT_BACKDIR}/${SERVER}-MySQL-backup-$database-${DATE}.sql.tar.gz ${CURRENT_BACKDIR}/${SERVER}-MySQL-backup-$database-${DATE}.sql
done

if  [ $DUMPALL = "y" ]; then
	rm ${CURRENT_BACKDIR}/dbs_on_${SERVER}.txt
fi

if [ $MOVETAR = "y" ]; then
echo "Moving sql.gz files to tar"
	for file in `ls ${CURRENT_BACKDIR}/*.gz`; do
		tar -rf ${CURRENT_BACKDIR}/${SERVER}-MySQL-backup-${DATE}.tar $file
		rm $file
	done
	EXT="tar"
else
	EXT="tar.gz"
fi

# If you have the mail program 'mutt' installed on
# your server, this script will have mutt attach the backup
# and send it to the email addresses in $EMAILS

if  [ $MAIL = "y" ] && [ $EMAILSENDON = $EMAILTODAY  ]; then
	BODY="MySQL backup is ready"
	ATTACH=`for file in ${CURRENT_BACKDIR}/*${DATE}.${EXT}; do echo -n "-a ${file} ";  done`

	echo "${BODY}" | mutt -s "${SUBJECT}" $ATTACH $EMAILS

	echo -e "MySQL backup has been emailed"
fi

if  [ $FTP = "y" ]; then
	echo "Initiating FTP connection..."
	cd $CURRENT_BACKDIR
	ATTACH=`for file in ${CURRENT_BACKDIR}/*${DATE}.sql.${EXT}; do echo -n -e "put $(basename $file)\n"; done`

	ftp -nv <<EOF
open $FTPHOST
user $FTPUSER $FTPPASS
cd $FTPDIR
passive
$ATTACH
quit
EOF
	echo -e  "FTP transfer complete"
fi

if  [ $ROTATE = "y" ]; then
	echo "Performing backup rotation..."

	# Convert the number of weeks and months to days
	MAX_WEEKS=$(($MAX_WEEKS * 7))
	MAX_MONTHS=$(($MAX_MONTHS * 31))

	# Daily backups
	if [ ! -d $ARCHIVE_PATH/$DAILY_PATH/$DATE ] && [ "$MAX_DAYS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$DAILY_PATH/$DATE
		# Copy files into archive dir
		find $CURRENT_BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$DAILY_PATH/$DATE/. \;
	fi

	# Delete old daily backups
	if [ -d $ARCHIVE_PATH/$DAILY_PATH ]; then
		find $ARCHIVE_PATH/$DAILY_PATH/ -maxdepth 1 -type d ! -name $DAILY_PATH -mtime +$MAX_DAYS -exec rm -Rf {} \;

		if [ "$MAX_DAYS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$DAILY_PATH/
		fi
	fi

	# Weekly backups
	WEEK_NO=`date +%V`
	DATE_WEEK="`date +'%Y-%m-'`$WEEK_NO"

	if [ ! -d $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK ] && [ "$MAX_WEEKS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK
		# Copy files into archive dir
		find $CURRENT_BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK/. \;
	fi

	# Delete old weekly backups
	if [ -d $ARCHIVE_PATH/$WEEKLY_PATH ]; then
		find $ARCHIVE_PATH/$WEEKLY_PATH/ -maxdepth 1 -type d ! -name $WEEKLY_PATH -mtime +$MAX_WEEKS -exec rm -Rf {} \;

		if [ "$MAX_WEEKS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$WEEKLY_PATH/
		fi
	fi

	# Monthly backups
	DATE_MONTH=`date +'%Y-%m'`

	if [ ! -d $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH ] && [ "$MAX_MONTHS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH
		# Copy files into archive dir
		find $CURRENT_BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH/. \;
	fi

	# Delete old monthly backups
	if [ -d $ARCHIVE_PATH/$MONTHLY_PATH ]; then
		find $ARCHIVE_PATH/$MONTHLY_PATH/ -maxdepth 1 -type d ! -name $MONTHLY_PATH -mtime +$MAX_MONTHS -exec rm -Rf {} \;

		if [ "$MAX_MONTHS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$MONTHLY_PATH/
		fi
	fi


	# Delete old backups in latest folder (-mtime +0 is 24 hours or older)
	find $BACKDIR/$LATEST_PATH/ -maxdepth 1 -type d ! -name $LATEST_PATH -mtime +0 -exec rm -Rf {} \;

	echo "Backups rotation complete"
fi

echo "MySQL backup is complete"
