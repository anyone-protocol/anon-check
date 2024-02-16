make exits

mkdir -p data/logs && touch data/logs/cron.log

/etc/init.d/check start

crontab -l | { cat; echo "*/$INTERVAL_MINUTES * * * * bash /opt/check/scripts/cpexits.sh >> /opt/check/data/logs/cron.log 2>&1"; } | crontab -

cron -f
