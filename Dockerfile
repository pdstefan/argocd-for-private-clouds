FROM ubuntu:18.04
USER root
RUN apt-get update && apt-get install -y \
    autossh \
    vim \
    net-tools \
    curl \
    dnsutils

COPY entrypoint.sh /entrypoint.sh
RUN chmod u+x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]


