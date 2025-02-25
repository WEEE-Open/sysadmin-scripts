# Source DB and repo passwords
source /data/containers/sources/mariadb/mariadb.env
source /data/containers/sources/mysql/mysql.env
source /data/containers/sources/postgres/postgres.env

# Set variables
RESTIC_REPOSITORY=sftp:rocco-backup:/data/boulangerie-backups/restic
SOURCE_DIR=/data/containers/sources
VOLUME_DIR=/data/containers/volumes
BACKUP_DIR=/data/containers/backups

# If $TYPE is not specified, assume manual backup
TYPE=${TYPE:-manual}

### Dump functions
#TODO: Make these more consistent wrt envs

mariadb_dump () {
	DB=$1
	DB_PASSWORD=$MARIADB_ROOT_PASSWORD
	OPTIONS=$2
	echo "--- MariaDB $DB ---"

	sudo podman exec -it mariadb-server mysqldump $OPTIONS -uroot -p$DB_PASSWORD $DB | gzip > $BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $BACKUP_DIR/backup-$DB.sql.gz"
}

mysql_dump () {
	DB=$1
	DB_PASSWORD=$MYSQL_ROOT_PASSWORD
	OPTIONS=$2
	echo "--- MySQL $DB ---"

	sudo podman exec -it mysql-server mysqldump $OPTIONS -uroot -p$DB_PASSWORD $DB | gzip > $BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $BACKUP_DIR/backup-$DB.sql.gz"
}

postgres_dump () {
	DB=$1
	OPTIONS=$2
	echo "--- PostgreSQL $DB ---"

	sudo PGPASSWORD=$POSTGRES_ROOT_PASSWORD podman exec -it postgres-server pg_dump -w $OPTIONS -Upostgres $DB | gzip > $BACKUP_DIR/backup-$DB.sql.gz
	echo "Created $BACKUP_DIR/backup-$DB.sql.gz"
}

#ldap_dump () {
	#TODO
#}

restic_backup () {
	NAME=$1
	FILES=$(printf "%s\n" "${@:2}")
	echo "--- Backing up $NAME ($TYPE) ---"

	# Create temp file
	echo $FILES > "wtb.tmp"
	sudo restic backup --repository $RESTIC_REPOSITORY --password-file /root/restic.txt --tag $NAME --tag $TYPE --verbose --files-from "wtb.tmp"
	# Delete temp file
	rm "wtb.tmp"
	echo "--- Backed up $NAME ($TYPE) ---"
}

### Backup functions

keycloak_backup () {
	postgres_dump "keycloak" "-C"
	restic_backup "keycloak" "$VOLUME_DIR/keycloak" "$BACKUP_DIR/backup-nextcloud.sql.gz"
}

#ldap_backup () {
	#TODO
#}

nginx_backup () {
	restic_backup "nginx" "$VOLUME_DIR/nginx"
}

opendkim_backup () {
	restic_backup "opendkim" "$VOLUME_DIR/opendkim"
}

postfix_backup () {
	restic_backup "postfix" "$VOLUME_DIR/postfix"
}
# Websites

bookstack_backup () {
	BASEDIR=$VOLUME_DIR/websites/bookstack
	mariadb_dump "bookstack_db" ""
	restic_backup "bookstack" "$BASEDIR/public/uploads" "$BASEDIR/storage/uploads" "$BASEDIR/.env" "$BACKUP_DIR/backup-bookstack_db.sql.gz"
}

crauto_backup () {
	restic_backup "crauto" "$VOLUME_DIR/websites/crauto/config/config.php"
}

nextcloud_backup () {
	BASEDIR=$VOLUME_DIR/websites/nextcloud
	postgres_dump "nextcloud" "-C"
	restic_backup "nextcloud" "$BASEDIR/data" "$BASEDIR/config" "$BACKUP_DIR/backup-nextcloud.sql.gz"
}

tarallo_backup () {
	mariadb_dump "tarallo_db" "--ignore-table=tarallo_db.ProductItemFeature --ignore-table=tarallo_db.ProductItemFeatureUnified"
	restic_backup "tarallo" "$VOLUME_DIR/websites/tarallo" "$BACKUP_DIR/backup-tarallo_db.sql.gz"
}

weeehire_backup () {
	restic_backup "weeehire" "$VOLUME_DIR/websites/weeehire/database/weeehire.db"
}

wordpress_backup () {
	restic_backup "wordpress" "$(ls -At $VOLUME_DIR/backups/wordpress/*.zip | head -n 1)"
}

yourls_backup () {
	restic_backup "yourls" "$VOLUME_DIR/websites/yourls"
}

# Sources

sources_backup () {
	restic_backup "sources" "$SOURCE_DIR"
}

if [[ "$TYPE" == "manual" ]]; then
	# Select service to backup with whiptail
	SERVICE_TO_BACKUP=$(whiptail --title "Select service to manually backup" --radiolist \
			"Select service to backup" 0 0 0 \
			"keycloak" "Keycloak" OFF \
			"ds389" "DS389" OFF \
			"nginx" "Nginx" OFF \
			"opendkim" "Opendkim" OFF \
			"postfix" "Postfix" OFF \
			"bookstack" "Bookstack" OFF \
			"crauto" "Crauto" OFF \
			"nextcloud" "Nextcloud" OFF \
			"tarallo" "Tarallo" OFF \
			"weeehire" "WEEEHire" OFF \
			"wordpress" "Wordpress" OFF \
            "yourls" "YOURLS" OFF \
            "sources" "Container sources" OFF \
			3>&1 1>&2 2>&3)

	# Execute the backup
	case $SERVICE_TO_BACKUP in
		"keycloak")
			keycloak_backup
			;;
		"ds389")
			ldap_backup
			;;
		"nginx")
			nginx_backup
			;;
		"opendkim")
			opendkim_backup
			;;
		"postfix")
			postfix_backup
			;;
		"bookstack")
			bookstack_backup
			;;
		"crauto")
			crauto_backup
			;;
		"nextcloud")
			nextcloud_backup
			;;
		"tarallo")
			tarallo_backup
			;;
		"weeehire")
			weeehire_backup
			;;
		"wordpress")
			wordpress_backup
			;;
		"yourls")
			yourls_backup
			;;
		"sources")
			sources_backup
			;;
		*)
			echo "Unknown service '$SERVICE_TO_BACKUP' to backup"
			;;
	esac
fi

if [[ "$TYPE" == "automatic" ]]; then
	keycloak_backup
	ldap_backup
	nginx_backup
	opendkim_backup
	postfix_backup

	# Websites
	bookstack_backup
	crauto_backup
	nextcloud_backup
	tarallo_backup
	weeehire_backup
	wordpress_backup
	yourls_backup

	# Sources
	sources_backup

	# Clean up old automatic backups
	# TODO

	# Clean up  old manual backups
	# TODO
fi