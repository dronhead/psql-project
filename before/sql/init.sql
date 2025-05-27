-- Создание пользователя test
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'test') THEN
        CREATE USER test WITH PASSWORD 'testpass';
    END IF;
END
$$;

-- Права доступа
GRANT CONNECT ON DATABASE demo TO test;
GRANT USAGE ON SCHEMA bookings TO test;
GRANT SELECT ON ALL TABLES IN SCHEMA bookings TO test;

-- (можно добавить CREATE EXTENSION, если нужно)
CREATE EXTENSION IF NOT EXISTS vector;

-- Пример запроса, экспортируемого в CSV (можно запускать отдельно)
-- SELECT * FROM flights
-- WHERE scheduled_departure BETWEEN '2017-03-01' AND '2017-03-31';
