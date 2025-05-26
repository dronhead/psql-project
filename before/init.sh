#!/usr/bin/env bash
set -euo pipefail

# Конфигурационные параметры
readonly DB_NAME="demo"
readonly DB_USER="postgres"
readonly TEST_USER="test"
readonly TEST_PASS="testpass"
readonly SQL_SOURCE="/tmp/demo.sql"
readonly OUTPUT_DIR="/var/www/html"
readonly CSV_FILE="${OUTPUT_DIR}/flights_march.csv"
readonly HTML_FILE="${OUTPUT_DIR}/index.html"

# Функция для выполнения SQL-запросов
pg_exec() {
    psql -U "${DB_USER}" -d postgres -v ON_ERROR_STOP=1 -c "$1"
}

# Инициализация базы данных
initialize_database() {
    echo "🛠 Инициализация базы данных..."

    # Завершаем активные подключения
    pg_exec "SELECT pg_terminate_backend(pg_stat_activity.pid)
             FROM pg_stat_activity
             WHERE pg_stat_activity.datname = '${DB_NAME}';" || true

    # Пересоздаем базу
    pg_exec "DROP DATABASE IF EXISTS ${DB_NAME};"
    pg_exec "CREATE DATABASE ${DB_NAME};"

    # Импортируем данные
    psql -U "${DB_USER}" -d "${DB_NAME}" -f "${SQL_SOURCE}"

    # Создаем расширение
    pg_exec "CREATE EXTENSION IF NOT EXISTS vector;"
}

# Основной скрипт
main() {
    # Проверка наличия SQL-файла
    if [ ! -f "${SQL_SOURCE}" ]; then
        echo "❌ Ошибка: SQL-файл не найден: ${SQL_SOURCE}"
        exit 1
    fi

    # Подготовка каталогов
    mkdir -p "${OUTPUT_DIR}"
    chown -R www-data:www-data "${OUTPUT_DIR}"

    # Очистка SQL-файла
    sed -i '/DROP DATABASE/Id; /CREATE DATABASE/Id; /^\\connect/d' "${SQL_SOURCE}"

    # Инициализация БД
    initialize_database

    # Создание пользователя
    echo "👤 Создание тестового пользователя..."
    psql -U "${DB_USER}" -d "${DB_NAME}" <<-SQL
        DO \$\$ BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${TEST_USER}') THEN
                CREATE USER ${TEST_USER} WITH PASSWORD '${TEST_PASS}';
            END IF;
        END \$\$;
        GRANT CONNECT ON DATABASE ${DB_NAME} TO ${TEST_USER};
        GRANT USAGE ON SCHEMA bookings TO ${TEST_USER};
        GRANT SELECT ON ALL TABLES IN SCHEMA bookings TO ${TEST_USER};
SQL

    # Экспорт данных
    echo "📤 Экспорт CSV..."
    psql -U "${DB_USER}" -d "${DB_NAME}" -c "\copy (
        SELECT *
        FROM flights
        WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31'
    ) TO '${CSV_FILE}' WITH (FORMAT CSV, HEADER);"

    # Генерация отчета
    generate_report
}

# Генерация HTML-отчета
generate_report() {
    echo "📝 Генерация HTML-гайда..."

    # Функция для выполнения запросов
    psqlc() {
        psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F',' -c "$1"
    }

    # Сбор данных
    local q1_res=$(psqlc "SELECT datname FROM pg_database WHERE datistemplate = false;")
    local q2_res=$(psqlc "SELECT usename FROM pg_user;")
    local q3_res=$(psqlc "SELECT grantee, privilege_type, table_name FROM information_schema.role_table_grants;")
    local q4_res=$(psqlc "SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'bookings';")
    local q5_res=$(psqlc "SELECT COUNT(*) FROM flights WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31';")

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

# Запуск основного скрипта
main
