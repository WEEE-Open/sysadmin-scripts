#!/bin/bash

THIS=$(realpath -s "$0")

ON_THE_SERVER=false
IGNORE_MISSING=false
# Check if parameteres are passed
if [[ $# -gt 0 ]]; then
	if [[ "$1" == "-s" ]]; then
		ON_THE_SERVER=true
		shift
	fi
	if [[ "$1" == "-i" ]]; then
		IGNORE_MISSING=true
		shift
	fi
fi

# Load passwords from env file
source .env

# Check if -i parameter is set
if [[ "$IGNORE_MISSING" != "true" ]]; then
	if [ ! -f .env ]; then
		echo -e "Env file not found!\nUse -i parameter to ignore this check."
		exit 1
	fi
	if [ -z $POSTGRES_ROOT_PASSWORD ]; then
		echo -e "Password for POSTGRES is not present.\nUse -i parameter to ignore this check."
		exit 1
	fi
	if [ -z $MYSQL_ROOT_PASSWORD ]; then
		echo -e "Password for MYSQL is not present.\nUse -i parameter to ignore this check."
		exit 1
	fi
	if [ -z $MARIADB_ROOT_PASSWORD ]; then
		echo "Password for MARIADB is not present.\nUse -i parameter to ignore this check."
		exit 1
	fi
fi

mariadb_backup () {
	if [ -z $MARIADB_ROOT_PASSWORD ]; then
		echo "Password for MARIADB is not present. Skipping backup task."
		return 0
	fi
	DB=$1
	DB_PASSWORD=$MARIADB_ROOT_PASSWORD
	OPTIONS=$2
	echo "--- MariaDB $DB ---"

	sudo podman exec -it mariadb-server mysqldump $OPTIONS -uroot -p$DB_PASSWORD $DB | gzip > $REMOTE_BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $REMOTE_BACKUP_DIR/backup-$DB.sql.gz"
}

mysql_backup () {
	if [ -z $MYSQL_ROOT_PASSWORD ]; then
		echo "Password for MYSQL is not present. Skipping backup task."
		return 0
	fi
	DB=$1
	DB_PASSWORD=$MYSQL_ROOT_PASSWORD
	OPTIONS=$2
	echo "--- MySQL $DB ---"

	sudo podman exec -it mysql-server mysqldump $OPTIONS -uroot -p$DB_PASSWORD $DB | gzip > $REMOTE_BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $REMOTE_BACKUP_DIR/backup-$DB.sql.gz"
}

postgres_backup () {
	if [ -z $POSTGRES_ROOT_PASSWORD ]; then
		echo "Password for POSTGRES is not present. Skipping backup task."
		return 0
	fi
	DB=$1
	OPTIONS=$2
	echo "--- PostgreSQL $DB ---"

	sudo PGPASSWORD=$POSTGRES_ROOT_PASSWORD podman exec -it postgres-server pg_dump -w $OPTIONS -Upostgres $DB | gzip > $REMOTE_BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $REMOTE_BACKUP_DIR/backup-$DB.sql.gz"
}

files_backup () {
	SHORTNAME=$1
	DIR=$2
	FILES=("${@:3}")
	echo "--- tar $DIR ($FILES) ---"

	sudo tar -czf $REMOTE_BACKUP_DIR/backup-$SHORTNAME.tar.gz -C $DIR "${FILES[@]}" ; sudo chown "$(id -un):" $REMOTE_BACKUP_DIR/backup-$SHORTNAME.tar.gz
	echo "Created $REMOTE_BACKUP_DIR/backup-$SHORTNAME.tar.gz"
}

files_backup_stream () {
	SHORTNAME=$1
	DIR=$2
	FILES=("${@:3}")
	echo "--- streaming tar $DIR ($FILES) ---"

	ssh boulangerie "sudo -S tar -czf - -C $DIR '${FILES[@]}'" | gzip > tmp/backup-$SHORTNAME.tar.gz
	echo "Created tmp/backup-$SHORTNAME.tar.gz (locally)"
}

move_files () {
	echo "--- Copying files ---"
	TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
	if [[ -d tmp ]]; then
		for file in tmp/*; do
			basename=$(basename $file)
			filename=$(basename $file | cut -d. -f1)
			ext=$(basename $file | cut -d. -f2-)
			mv "$file" "${filename}-${TIMESTAMP}.${ext}"
			echo "Done: ${filename}-${TIMESTAMP}.${ext}"
		done
		rmdir tmp
	else
		echo "tmp is not a directory or does not exist"
		exit 1
	fi
}

notify () {
	notify-send -i drive-harddisk "Backup performed"
}

# Script is being executed on the server, so run the jobs
if [[ "$ON_THE_SERVER" == "true" ]]; then
	rm -rf $REMOTE_BACKUP_DIR
    mkdir $REMOTE_BACKUP_DIR

    while [[ $# -gt 0 ]]; do
		case $1 in
			bookstack_db)
			mariadb_backup "bookstack_db" ""
			shift
			;;
			tarallo_db)
			mariadb_backup "tarallo_db" "--ignore-table=tarallo_db.ProductItemFeature --ignore-table=tarallo_db.ProductItemFeatureUnified"
			shift
			;;
			nextcloud)
			postgres_backup "nextcloud" "-C"
			shift
			;;
			keycloak)
			postgres_backup "keycloak" "-C"
			shift
			;;
			weeebsite)
			mysql_backup "weeebsite" ""
			shift
			;;
			bookstack-dir)
			files_backup "bookstack-dir" "/data/containers/volumes/websites/bookstack" "public/uploads" "storage/uploads" ".env"
			shift
			;;
			weeebsite-dir)
			files_backup "weeebsite-dir" "/data/containers/volumes/websites/wordpress" "wp-content/uploads" "wp-content/gallery" "wp-config.php"
			shift
			;;
			weeehire)
			files_backup "weeehire" "/data/containers/volumes/websites/weeehire" "database/weeehire.db"
			shift
			;;
			containers)
			files_backup "containers" "/data/containers/sources" "."
			shift
			;;
			nginx)
			files_backup "nginx" "/data/containers/volumes/nginx" "configuration"
			shift
			;;
# 			nextcloud-dir)
# 			files_backup "nextcloud-dir" "/data/containers/volumes/websites/nextcloud" "data" "config"
# 			shift
# 			;;
			*)
			echo "Unknown backup $1"
			shift
			;;
		esac
	done
# Script is not running on the server, select backup tasks
else
	if [[ $# -lt 1 ]]; then
		# https://stackoverflow.com/a/1970254
		WHAT_TO_BACKUP=$(whiptail --title "Select backups" --checklist \
			"Select backups" 0 0 0 \
			"containers" "Container sources" OFF \
			"nginx" "Nginx config" OFF \
			"bookstack_db" "Bookstack DB" OFF \
			"bookstack-dir" "Bookstack files" OFF \
			"tarallo_db" "Tarallo DB" OFF \
			"nextcloud" "Nextcloud DB" OFF \
			"keycloak" "Keycloak DB" OFF \
			"weeebsite" "Weeebsite DB" OFF \
			"weeebsite-dir" "Weeebsite files" OFF \
			"weeehire" "WEEEHire DB" OFF \
			"nextcloud-dir" "Nextcloud files (streaming)" OFF \
			3>&1 1>&2 2>&3)
	fi
	if [[ "x" == "x$WHAT_TO_BACKUP" ]]; then
		echo "Nothing to do"
		exit 1
	fi

	# Copy the script on server and set permissions
 	scp $THIS $SERVER:boulangerie-backup-script.sh
	ssh -t $SERVER "bash -s <<EOF
    !/bin/bash
    set -e
    chmod ug+x boulangerie-backup-script.sh
    chmod o-r boulangerie-backup-script.sh
    ./boulangerie-backup-script.sh -s $WHAT_TO_BACKUP
EOF"

	echo "--- rsync ---"

	rsync -raHAX --info=progress2 boulangerie:$REMOTE_BACKUP_DIR/ tmp/

	while [[ $# -gt 0 ]]; do
		case $1 in
			nextcloud-dir)
			files_backup_stream "nextcloud-dir" "/data/containers/volumes/websites/nextcloud"
			shift
			;;
		esac
	done

	move_files
	notify
fi

