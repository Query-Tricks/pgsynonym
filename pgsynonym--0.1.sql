-- PRESET
DO $$
DECLARE
    original_path TEXT;
    filtered_path TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgsynonym') THEN
        CREATE role pgsynonym nologin;
    END IF;
    CREATE SCHEMA pgsynonym;
    ALTER SCHEMA pgsynonym OWNER TO pgsynonym;
    
    original_path := current_setting('search_path')::text;
    filtered_path := replace(original_path, ', pg_temp', '');
    EXECUTE format('SET search_path TO pgsynonym, %s', filtered_path);

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;

    EXECUTE format('ALTER ROLE %s SET search_path TO pgsynonym, %s', current_user, filtered_path);
END $$;


-- PGSYNONYM CREATE
CREATE OR REPLACE FUNCTION pgsynonym_create(source_object_name TEXT, target_object_name TEXT)
RETURNS TEXT AS $$
DECLARE
    source_schema text;
    source_object text;
    object_type text;
    rec record;
    query text;
    param_list text;
    arr_length int;
    i int;
BEGIN
    IF source_object_name LIKE '%.%' THEN
        source_schema := split_part(source_object_name, '.', 1);
        source_object := split_part(source_object_name, '.', 2);
    ELSE
        RAISE EXCEPTION 'Invalid object name format. Expected format: [schema].[object_name]';
    END IF;

    SELECT type INTO object_type FROM (
        SELECT DISTINCT CASE 
                            WHEN c.relkind = 'r' THEN 'TABLE'
                            WHEN p.prokind = 'p' THEN 'PROCEDURE'
                            WHEN p.prokind = 'f' THEN 'FUNCTION'
                        END as type
        FROM pg_catalog.pg_class c
            FULL OUTER JOIN pg_catalog.pg_proc p ON c.relname = p.proname
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = COALESCE(c.relnamespace, p.pronamespace)
        WHERE n.nspname = source_schema
          AND (c.relname = source_object OR p.proname = source_object)
    ) AS subquery;

    IF object_type IS NULL THEN
        RAISE EXCEPTION 'Object does not exist or is not a supported type.';
    END IF;

    IF object_type = 'TABLE' THEN
        query := format('CREATE OR REPLACE VIEW pgsynonym.%I AS SELECT * FROM %I.%I;', target_object_name, source_schema, source_object);
        EXECUTE query;
    ELSE
        FOR rec IN
            SELECT 
                pg_catalog.pg_get_function_result(p.oid) as "result_data_type",
                pg_catalog.pg_get_function_arguments(p.oid) as "argument_data_types"
            FROM pg_catalog.pg_proc p
                LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = source_schema
                AND p.proname = source_object
                AND pg_catalog.pg_function_is_visible(p.oid)
                AND n.nspname <> 'pg_catalog'
                AND n.nspname <> 'information_schema'
        LOOP
            query := '';
            param_list := '';
            arr_length := array_length(string_to_array(rec.argument_data_types, ','), 1);
            IF arr_length IS NULL THEN
                param_list := '';
            ELSE
                FOR i IN 1..arr_length LOOP
                    IF param_list != '' THEN
                        param_list := param_list || ', ';
                    END IF;
                    param_list := param_list || '$' || i;
                END LOOP;
            END IF;
            IF object_type = 'PROCEDURE' THEN
                query := format('CREATE OR REPLACE PROCEDURE pgsynonym.%I(%s) LANGUAGE plpgsql AS $func$ BEGIN CALL %I.%I(%s); END; $func$;', target_object_name, rec.argument_data_types, source_schema, source_object, param_list);
            ELSIF object_type = 'FUNCTION' THEN
                query := format('CREATE OR REPLACE FUNCTION pgsynonym.%I(%s) RETURNS %s AS $func$ BEGIN RETURN %I.%I(%s); END; $func$ LANGUAGE plpgsql;', target_object_name, rec.argument_data_types, rec.result_data_type, source_schema, source_object, param_list);
            ELSE
                RAISE EXCEPTION 'Object does not exist or is not a supported type.';
            END IF;
            EXECUTE query;
        END LOOP;
    END IF;
    RETURN 'SYNONYM ' || object_type || ' CREATED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- PGSYNONYM DROP
CREATE OR REPLACE FUNCTION pgsynonym_drop(pgsynonym_name TEXT)
RETURNS TEXT AS $$
DECLARE
    object_type text;
    rec record;
    query text;
    param_list text;
    arr_length int;
    i int;
BEGIN
    SELECT type INTO object_type FROM (
        SELECT DISTINCT CASE 
                            WHEN c.relkind = 'v' THEN 'VIEW'
                            WHEN p.prokind = 'p' THEN 'PROCEDURE'
                            WHEN p.prokind = 'f' THEN 'FUNCTION'
                        END as type
        FROM pg_catalog.pg_class c
            FULL OUTER JOIN pg_catalog.pg_proc p ON c.relname = p.proname
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = COALESCE(c.relnamespace, p.pronamespace)
        WHERE n.nspname = 'pgsynonym'
          AND (c.relname = pgsynonym_name OR p.proname = pgsynonym_name)
    ) AS subquery;

    IF object_type IS NULL THEN
        RAISE EXCEPTION 'Object does not exist or is not a supported type.';
    END IF;

    IF object_type = 'VIEW' THEN
        query := format('DROP VIEW pgsynonym.%I;', pgsynonym_name);
        EXECUTE query;
    ELSE
        FOR rec IN
            SELECT 
                pg_catalog.pg_get_function_result(p.oid) as "result_data_type",
                pg_catalog.pg_get_function_arguments(p.oid) as "argument_data_types"
            FROM pg_catalog.pg_proc p
                LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'pgsynonym'
                AND p.proname = pgsynonym_name
                AND pg_catalog.pg_function_is_visible(p.oid)
                AND n.nspname <> 'pg_catalog'
                AND n.nspname <> 'information_schema'
        LOOP
            query := '';
            param_list := '';
            arr_length := array_length(string_to_array(rec.argument_data_types, ','), 1);
            IF arr_length IS NULL THEN
                param_list := '';
            ELSE
                FOR i IN 1..arr_length LOOP
                    IF param_list != '' THEN
                        param_list := param_list || ', ';
                    END IF;
                    param_list := param_list || '$' || i;
                END LOOP;
            END IF;
            IF object_type = 'PROCEDURE' THEN
                query := format('DROP PROCEDURE pgsynonym.%I(%s);', pgsynonym_name, rec.argument_data_types);
            ELSIF object_type = 'FUNCTION' THEN
                query := format('DROP FUNCTION pgsynonym.%I(%s);', pgsynonym_name, rec.argument_data_types);
            ELSE
                RAISE EXCEPTION 'Object does not exist or is not a pgsynonym object.';
            END IF;
            EXECUTE query;
        END LOOP;
    END IF;
    RETURN 'PGSYNONYM ' || object_type || ' DROPED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;


-- GRANT PRIVILEGES
CREATE OR REPLACE FUNCTION pgsynonym_grant(user_name TEXT, target_synonym TEXT, privileges TEXT)
RETURNS TEXT as $$
BEGIN
    EXECUTE 'GRANT ' || privileges || ' ON pgsynonym.' || target_synonym || ' TO ' || user_name || ';';
    EXECUTE 'GRANT USAGE ON SCHEMA pgsynonym TO ' || user_name || ';';
    EXECUTE 'ALTER ROLE '||quote_ident(user_name)||' SET search_path = pgsynonym, "$user", public';
    RETURN 'SYNONYM GRANTED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- REVOKE PRIVILEGES
CREATE OR REPLACE FUNCTION pgsynonym_revoke(user_name TEXT, target_synonym TEXT, privileges TEXT)
RETURNS TEXT as $$
BEGIN
    EXECUTE 'REVOKE ' || privileges || ' ON pgsynonym.' || target_synonym || ' FROM ' || user_name || ';';
    EXECUTE 'REVOKE USAGE ON SCHEMA pgsynonym FROM ' || user_name || ';';
    EXECUTE 'ALTER ROLE '||quote_ident(user_name)||' SET search_path = "$user", public';
    RETURN 'SYNONYM REVOKED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;
