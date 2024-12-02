# Source DB passwords
source /data/containers/sources/mariadb/mariadb.env
source /data/containers/sources/mysql/mysql.env
source /data/containers/sources/postgres/postgres.env

REPO=restic-demo
RESTORE_DIR=restore-demo
VOLUME_DIR=/data/containers/volumes

# 1. select service to restore
SERVICE_TO_RESTORE=$(whiptail --title "Select service to restore" --radiolist \
			"Select service to restore" 0 0 0 \
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
			3>&1 1>&2 2>&3)

# 1.2 get list of snapshots of selected
restic snapshots -r $REPO | grep $SERVICE_TO_RESTORE > "ids.tmp"

sorted_data=$(sort -k2,3r "ids.tmp" | awk '
{
    id = $1;
    datetime = $2 " " $3;
    tags = $5;
    size = $NF;

    printf "%s %s %s %s\n", id, datetime, tags, size;
}')
rm "ids.tmp"

entries=()
while IFS= read -r line; do
    [ -z "$line" ] && continue

    id=$(echo "$line" | awk '{print $1}')
    date=$(echo "$line" | awk '{print $2}')
    tags=$(echo "$line" | awk '{print $3}')

    entries+=("$id" "$datetime $tags" "OFF")
done <<< "$sorted_data"

if [ ${#entries[@]} -eq 0 ]; then
    echo "There are no snapshots available for $SERVICE_TO_RESTORE."
    exit 0
fi

# 2. select which snapshot has to be restored
SNAPSHOT_TO_RESTORE=$(whiptail --radiolist "Select snapshot to restore:" 0 0 0 "${entries[@]}" 3>&1 1>&2 2>&3)

# 3. restore files (and DB)
echo "--- Restoring snapshot $SNAPSHOT_TO_RESTORE ($SERVICE_TO_RESTORE) ---"
restic -r $REPO restore $SNAPSHOT_TO_RESTORE --verbose --target $RESTORE_DIR
echo "--- Restored snapshot $SNAPSHOT_TO_RESTORE ($SERVICE_TO_RESTORE) ---"

case $SERVICE_TO_RESTORE in
    "keycloak")
        keycloak_restore
        ;;
    "ds389")
        ldap_restore
        ;;
    "nginx")
        nginx_restore
        ;;
    "opendkim")
        opendkim_restore
        ;;
    "postfix")
        postfix_restore
        ;;
    "bookstack")
        bookstack_restore
        ;;
    "crauto")
        crauto_restore
        ;;
    "nextcloud")
        nextcloud_restore
        ;;
    "tarallo")
        tarallo_restore
        ;;
    "weeehire")
        weeehire_restore
        ;;
    "wordpress")
        wordpress_restore
        ;;
    "yourls")
        yourls_restore
        ;;
    *)
        echo "Unknown service $SERVICE_TO_RESTORE to restore"
        ;;
esac

### DB restore functions

mariadb_restore (){
    DB=$1
    FILE=$2
	DB_PASSWORD=$MARIADB_ROOT_PASSWORD
	echo "--- MariaDB $DB ---"

    sudo podman exec -it mariadb-server zcat "$FILE" | mysql -uroot -p $DB_PASSWORD $DB
	echo "Restored $FILE"
}

mysql_restore () {
	DB=$1
    FILE=$2
	DB_PASSWORD=$MYSQL_ROOT_PASSWORD
	echo "--- MySQL $DB ---"

	sudo podman exec -it mysql-server zcat "$FILE" | mysql -uroot -p $DB_PASSWORD $DB
	echo "Restored $FILE"
}

postgres_restore () {
	DB=$1
	FILE=$2
	echo "--- PostgreSQL $DB ---"

	sudo PGPASSWORD=$POSTGRES_ROOT_PASSWORD podman exec -it postgres-server zcat "$FILE" | psql -Upostgres $DB
	echo "Restored $FILE"
}

ldap_restore () {
	#TODO
}


### Restore functions

keycloak_restore () {
	postgres_restore "keycloak" "$RESTORE_DIR/backup-keycloak.sql.gz"
    cp -R "$RESTORE_DIR/keycloak/." "$VOLUME_DIR/keycloak"
}

ldap_restore () {
	#TODO
}

nginx_restore () {
    cp -R "$RESTORE_DIR/nginx/." "$VOLUME_DIR/nginx"
}

opendkim_restore () {
    cp -R "$RESTORE_DIR/opendkim/." "$VOLUME_DIR/opendkim"
}

postfix_restore () {
	cp -R "$RESTORE_DIR/postfix/." "$VOLUME_DIR/postfix"
}

# Websites

bookstack_restore () {
	BASEDIR=$VOLUME_DIR/websites/bookstack
	mariadb_restore "bookstack_db" "$RESTORE_DIR/backup-bookstack_db.sql.gz"
    cp -R "$RESTORE_DIR/{public/uploads/.,storage/uploads/.,.env}" "$BASEDIR/"
}

crauto_restore () {
    cp "$RESTORE_DIR/websites/crauto/config/config.php" "$VOLUME_DIR/websites/crauto/config/config.php"
}

nextcloud_restore () {
	BASEDIR=$VOLUME_DIR/websites/nextcloud
	postgres_restore "nextcloud" "$RESTORE_DIR/backup-nextcloud.sql.gz"
    cp -R "$RESTORE_DIR/{data/.,config/.}" "$BASE_DIR/" 
}

tarallo_restore () {
	mariadb_restore "tarallo_db" "$RESTORE_DIR/backup-tarallo_db.sql.gz"
	cp -R "$RESTORE_DIR/websites/tarallo/." "$VOLUME_DIR/websites/tarallo"
}

weeehire_restore () {
    cp "$RESTORE_DIR/websites/weeehire/database/weeehire.db" "$VOLUME_DIR/websites/weeehire/database/weeehire.db"
}

wordpress_restore () {
	mysql_restore "weeebsite" "??filename??"
	#TODO
}

yourls_restore () {
    cp -R "$RESTORE_DIR/websites/yourls/." "$VOLUME_DIR/websites/yourls"
}

# Sources

sources_restore () {
    cp -R "$RESTORE_DIR/." "$SOURCE_DIR"
}