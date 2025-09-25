#!/bin/bash
LINE= # The entire line to comment out, whitespace included
CONFIG= # The location of the file to edit
TIMER= # The amount of time the login page stays unlocked
URL= # The URL to your Nextcloud instance
RELOAD= # The command to reload your reverse proxy

echo "Unlocking direct login..."
sed -i "s/$LINE/#$LINE/g" $CONFIG
eval $RELOAD
echo "Done. You have $TIMER seconds to visit $URL/login?direct=1 and log in as admin."
sleep $TIMER
echo "Time's up. Locking direct login..."
sed -i "s/#$LINE/$LINE/g" $CONFIG
eval $RELOAD
