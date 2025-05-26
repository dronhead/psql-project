FROM ubuntu:20.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential=12.8* \
    wget=1.20* \
    gnupg2=2.2* \
    lsb-release=11.1* \
    git=1:2.25* \
    ca-certificates=202* && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-server-dev-15=15* && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /pgvector
RUN git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git . && \
    make && \
    make install

FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget=1.20* \
    ca-certificates=202* \
    gnupg2=2.2* \
    lsb-release=11.1* \
    unzip=6.0* \
    nginx=1.18* && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-15=15* \
    postgresql-client-15=15* && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/postgresql/15/lib/ /usr/lib/postgresql/15/lib/
COPY --from=builder /usr/share/postgresql/15/extension/ /usr/share/postgresql/15/extension/
COPY demo.sql /tmp/demo.sql
COPY nginx.conf /etc/nginx/sites-available/default
COPY init.sh /init.sh

RUN chmod +x /init.sh && \
    mkdir -p /var/lib/postgresql/data /var/www/html && \
    chown -R postgres:postgres /var/lib/postgresql && \
    chown -R www-data:www-data /var/www/html

CMD ["/init.sh"]
