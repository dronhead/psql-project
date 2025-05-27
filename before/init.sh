#!/bin/bash
set -euo pipefail

readonly DB_NAME="demo"
readonly DB_USER="postgres"
readonly TEST_USER="test"
readonly TEST_PASS="testpass"
readonly SQL_SOURCE="/tmp/demo.sql"
readonly OUTPUT_DIR="/var/www/html"
readonly CSV_FILE="${OUTPUT_DIR}/flights_march.csv"
readonly HTML_FILE="${OUTPUT_DIR}/index.html"
readonly SQL_SCRIPTS_DIR="/sql"

initialize_postgres() {
    echo "🛠 Инициализация PostgreSQL..."

    if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
        su - postgres -c "/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data"

        # Конфигурация PostgreSQL
        echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/postgresql/data/pg_hba.conf
        echo "listen_addresses = '*'" >> /var/lib/postgresql/data/postgresql.conf
        echo "max_wal_size = 1GB" >> /var/lib/postgresql/data/postgresql.conf
    fi

    # Запуск PostgreSQL в фоне
    su - postgres -c "/usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data" &

    # Ожидание готовности
    until pg_isready -U postgres -h 127.0.0.1; do
        sleep 1
    done
}

start_nginx() {
    echo "🌐 Запуск Nginx..."
    nginx -g "daemon off;" &
}

setup_database() {
    echo "🛢 Настройка базы данных..."

    # Создание базы
    psql -U postgres -c "CREATE DATABASE ${DB_NAME};" || true

    # Импорт основной схемы и данных
    psql -U postgres -d "${DB_NAME}" -f "${SQL_SOURCE}"

    # Выполнение всех SQL-запросов из отдельного файла
    psql -U postgres -d "${DB_NAME}" -f "/sql/init.sql"

    #Экспорт CSV
    echo "📤 Экспорт CSV..."
    psql -U "${DB_USER}" -d "${DB_NAME}" -c "\copy (
        SELECT *
        FROM flights
        WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31'
    ) TO '${CSV_FILE}' WITH (FORMAT CSV, HEADER);"

    generate_report
}

# Генерация HTML-отчета
generate_report() {
    echo "📝 Генерация HTML-гайда..."

    # Функция для выполнения запросов
    psqlc() {
        psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F',' -c "$1"
    }

    # Создание HTML-файла
    cat > "${HTML_FILE}" <<-HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>PostgreSQL Demo Guide</title>
    <style>
        body { font-family: sans-serif; margin: 40px; line-height: 1.6; }
        h1, h2 { color: #2c3e50; }
        .example { background: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 5px; }
        pre { background: #2c3e50; color: white; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .result { background: #e9ecef; padding: 15px; margin: 10px 0; border-radius: 5px; }
        a { color: #3498db; text-decoration: none; }
    </style>
</head>
<body>
    <h1>📚 Руководство по работе с PostgreSQL</h1>

    <div class="example">
        <h2>1. Список баз данных</h2>
        <pre>SELECT datname FROM pg_database WHERE datistemplate = false;</pre>
    </div>

    <div class="example">
        <h2>2. Список пользователей</h2>
        <pre>SELECT usename FROM pg_user;</pre>
    </div>

    <div class="example">
        <h2>3. Права доступа</h2>
        <pre>SELECT grantee, privilege_type, table_name FROM information_schema.role_table_grants;</pre>
    </div>

    <div class="example">
        <h2>4. Структура таблиц</h2>
        <pre>SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bookings';</pre>
    </div>

    <div class="example">
        <h2>5. Данные за март 2017</h2>
        <pre>SELECT COUNT(*) FROM flights
WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31';</pre>
        <p><a href="flights_march.csv">🗄 Скачать полные данные (CSV)</a></p>
    </div>

    <div class="example">
        <h2>6. Пример создания пользователя</h2>
        <pre>CREATE USER ${TEST_USER} WITH PASSWORD '${TEST_PASS}';
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${TEST_USER};
GRANT SELECT ON ALL TABLES IN SCHEMA bookings TO ${TEST_USER};</pre>
    </div>
</body>
</html>
HTML

    echo "✅ Готово! Откройте http://localhost в браузере"
}

main() {
    # Инициализация и запуск сервисов
    initialize_postgres
    start_nginx

    # Настройка базы данных
    setup_database

    # Генерация отчетов
    generate_report

    # Поддержание работы контейнера
    echo "✅ Все сервисы запущены"
    tail -f /dev/null
}
# Запуск основного скрипта
main
