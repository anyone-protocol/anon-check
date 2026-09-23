#!/bin/sh

cd /opt/check

mkdir -p data/consensuses data/descriptors data/logs && touch data/logs/cron.log

# A truncated exit-policies file stops the server from starting at all, so check
# it before we hand it over.
python3 scripts/repair-exit-policies.py

# Serve from the data already on the volume first. Rebuilding it reads every
# consensus the collector offers, which outlasted the health check grace and put
# the task in a restart loop, so that work happens in the background now and the
# server picks it up on SIGUSR2.
/etc/init.d/check start

(
  make exits && kill -s USR2 "$(cat /var/run/check.pid)"
) &

crontab -l | { cat; echo "*/$INTERVAL_MINUTES * * * * bash /opt/check/scripts/cpexits.sh >> /opt/check/data/logs/cron.log 2>&1"; } | crontab -

cron -f
