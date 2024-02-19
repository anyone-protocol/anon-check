FROM debian:bookworm

RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y \
    make git golang wget python3-dateutil python3-stem cron

ADD .. /opt/check/temp

WORKDIR /opt/check

RUN cd temp && \
    make install && \
    cp -r Makefile public scripts docker/docker-entrypoint.sh .. && \
    cd .. && \
    rm -rf temp

EXPOSE 8000

ENTRYPOINT [ "sh", "docker-entrypoint.sh" ]
