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


CREATE EXTENSION IF NOT EXISTS vector;
