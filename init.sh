#!/usr/bin/env bash
set -euo pipefail

readonly db_name="demo"
readonly db_user="postgres"
readonly test_user="test"
readonly test_pass="testpass"
readonly demo_zip="demo-big.zip"
readonly demo_sql="demo-big.sql"
readonly output_dir="/var/www/html"
readonly csv_file="${output_dir}/flights_march.csv"
readonly html_file="${output_dir}/index.html"

# Скачать и подготовить SQL
if [ ! -f "/tmp/${demo_sql}" ]; then
  echo "📦 Скачивание демо-схемы..."
  wget -O "/tmp/${demo_zip}" https://edu.postgrespro.ru/demo-big.zip
  unzip "/tmp/${demo_zip}" -d /tmp
  found_sql=$(find /tmp -name "demo-big-*.sql" | head -n 1 || true)
  [ -z "$found_sql" ] && echo "❌ SQL-файл не найден" && exit 1
  mv "$found_sql" "/tmp/${demo_sql}"

  # Удаляем конфликтные команды из SQL
  sed -i '/DROP DATABASE/Id' "/tmp/${demo_sql}"
  sed -i '/CREATE DATABASE/Id' "/tmp/${demo_sql}"
fi

# Пересоздание базы
psql -U "$db_user" -d postgres -v ON_ERROR_STOP=1 <<-SQL
  DROP DATABASE IF EXISTS ${db_name};
  CREATE DATABASE ${db_name};
SQL

psql -U "$db_user" -d "$db_name" -v ON_ERROR_STOP=1 -f "/tmp/${demo_sql}"
psql -U "$db_user" -d "$db_name" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Функция запроса с CSV-выводом
psqlc() {
  psql -U "$db_user" -d "$db_name" -t -A -F',' -c "$1"
}

# SQL-запросы
readonly q_dbs="SELECT datname FROM pg_database;"
readonly q_users="SELECT usename FROM pg_user;"
readonly q_privs="SELECT grantee||':'||table_name||':'||privilege_type FROM information_schema.role_table_grants;"
readonly q_columns="SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, ordinal_position;"
readonly q_march="SELECT * FROM flights WHERE scheduled_departure BETWEEN '2025-03-01' AND '2025-03-31'"

# Выполнение
res_dbs=$(psqlc "$q_dbs")
res_users=$(psqlc "$q_users")
res_privs=$(psqlc "$q_privs")
res_columns=$(psqlc "$q_columns")
res_count=$(psqlc "SELECT COUNT(*) FROM flights WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31';")
res_preview=$(psqlc "$q_march" | head -n 20)

# Создание test-пользователя
psql -U "$db_user" -d "$db_name" <<-SQL
  DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${test_user}') THEN
      CREATE USER ${test_user} WITH PASSWORD '${test_pass}';
    END IF;
  END\$\$;
  GRANT CONNECT ON DATABASE ${db_name} TO ${test_user};
  GRANT USAGE ON SCHEMA public TO ${test_user};
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${test_user};
SQL

echo "📤 Экспорт CSV..."
psql -U postgres -d demo -c "\copy (
  SELECT *
  FROM flights
  WHERE EXTRACT(MONTH FROM scheduled_departure) = 3
) TO '${csv_file}' WITH CSV HEADER"

# Генерация HTML-гайда
echo "📝 Генерация HTML-гайда"
cat > "$html_file" <<-HTML
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>PostgreSQL Demo Guide</title>
  <style>
    body { font-family: sans-serif; margin: 40px; line-height: 1.5; }
    h1, h2 { color: #333; }
    pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; }
    code { font-family: monospace; }
    a { color: #0066cc; }
  </style>
</head>
<body>
  <h1>PostgreSQL Demo: SQL‑запросы и Bash‑скрипт</h1>

  <h2>1. Список всех баз данных</h2>
  <pre><code>psql -U postgres -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false;"</code></pre>

  <h2>2. Список всех пользователей</h2>
  <pre><code>psql -U postgres -d postgres -c "SELECT usename FROM pg_user;"</code></pre>

  <h2>3. Права для каждого пользователя</h2>
  <pre><code>psql -U postgres -d postgres -c "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication FROM pg_roles;"</code></pre>

  <h2>4. Все поля в базе <code>demo</code></h2>
  <pre><code>psql -U postgres -d demo -c "
SELECT table_name, column_name, data_type
  FROM information_schema.columns
 WHERE table_schema = 'bookings';
"</code></pre>

  <h2>5. Создание пользователя <code>test</code> с правами чтения</h2>
  <pre><code>-- если юзер уже есть, создавать не будет
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'test'
  ) THEN
    CREATE ROLE test WITH LOGIN PASSWORD 'testpassword';
  END IF;
END
$$;
GRANT CONNECT ON DATABASE demo TO test;
GRANT USAGE, SELECT ON ALL TABLES IN SCHEMA public TO test;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO test;
</code></pre>

  <h2>6. Запрос данных о полётах за март</h2>
  <pre><code>psql -U postgres -d demo -c "
  SELECT *
  FROM flights
 WHERE EXTRACT(MONTH FROM scheduled_departure) = 3;"</code></pre>

  <h2>7. Экспорт в CSV и запуск скрипта</h2>
  <pre><code>docker-compose up -d
docker-compose exec db bash /scripts/execute_queries.sh</code></pre>

  <h2>8. Готовый CSV</h2>
  <p><a href="flights_march.csv">Скачать flights_march.csv</a></p>

  <hr>
  <p>Все команды и скрипты можно повторно запускать без ошибок — они проверяют существование ролей и перезаписывают CSV.</p>
</body>
</html>
HTML

# Права (если root)
[ "$(id -u)" = "0" ] && chown -R www-data:www-data "$output_dir"

echo "✅ Всё готово. Открой http://localhost чтобы увидеть результат"