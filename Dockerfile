# Стадия сборки: pgvector
FROM ubuntu:20.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential wget gnupg2 lsb-release git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Добавляем репозиторий PostgreSQL
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y postgresql-server-dev-15 \
    && rm -rf /var/lib/apt/lists/*

# Клонируем и собираем pgvector
RUN git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git /pgvector \
    && cd /pgvector && make && make install

# Стадия выполнения: установка PostgreSQL и nginx
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget ca-certificates gnupg2 lsb-release unzip nginx \
    && rm -rf /var/lib/apt/lists/*

# Добавляем PostgreSQL-репозиторий
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
    postgresql-15 postgresql-client-15 \
    && rm -rf /var/lib/apt/lists/*

# Копируем собранный pgvector
COPY --from=builder /usr/lib/postgresql/15/lib/ /usr/lib/postgresql/15/lib/
COPY --from=builder /usr/share/postgresql/15/extension/ /usr/share/postgresql/15/extension/

# Копируем скрипты и конфиг
COPY nginx.conf /etc/nginx/sites-available/default
COPY init.sh /init.sh
RUN chmod +x /init.sh

# Создаем директории и выставляем права
RUN mkdir -p /var/lib/postgresql/data /var/www/html && \
    chown -R postgres:postgres /var/lib/postgresql && \
    chown -R www-data:www-data /var/www/html

# Запуск PostgreSQL, nginx и скрипта
CMD bash -c "\
  su - postgres -c '[ -f /var/lib/postgresql/data/PG_VERSION ] || /usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data' && \
  su - postgres -c '/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data -w start' && \
  /init.sh && \
  nginx -g 'daemon off;'"