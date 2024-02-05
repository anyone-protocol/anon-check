FROM debian:bookworm

RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y \
    make git golang gettext wget python3-dateutil python3-stem cron

#RUN git clone https://gitlab.torproject.org/tpo/network-health/metrics/tor-check.git /opt/check && \
#    cd /opt/check

ADD . /opt/check 

RUN chmod 0744 /opt/check/scripts/cpexits.sh

RUN crontab -l | { cat; echo "* * * * * bash /opt/check/scripts/cpexits.sh"; } | crontab -

EXPOSE 8000

ENTRYPOINT [ "/opt/check/scripts/docker-entrypoint" ]

CMD [ "cron", "-f"]
