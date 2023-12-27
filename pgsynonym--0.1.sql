-- PRESET
DO $$
DECLARE
    original_path TEXT;
    filtered_path TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgsynonym') THEN
        CREATE USER pgsynonym superuser;
    END IF;
    CREATE SCHEMA pgsynonym;
    ALTER SCHEMA pgsynonym OWNER TO pgsynonym;
    
    IF NOT EXISTS (select 1 from pg_tables where schemaname = 'pgsynonym' and tablename = 'pgsynonym_info') THEN
        CREATE TABLE pgsynonym.pgsynonym_info(
            synonym_schema text,
            synonym_name text,
            origin_object_schema text,
            origin_object text,
            origin_type text,
            attributes text,
            creation_date timestamp,
            status text,
            comments text
        );
    END IF;
    original_path := current_setting('search_path')::text;
    filtered_path := replace(original_path, ', pg_temp', '');
END $$;

-- PGSYNONYM CREATE
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_create(source_object_name TEXT, target_object_name TEXT)
RETURNS TEXT AS $$
DECLARE
    source_schema text;
    source_object text;
    target_schema text;
    target_object text;
    object_type text;
    rec record;
    query text;
    param_list text;
    arr_length int;
    i int;
    nowdate timestamp;
    column_list text;
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;
    IF source_object_name LIKE '%.%' THEN
        source_schema := split_part(source_object_name, '.', 1);
        source_object := split_part(source_object_name, '.', 2);
    ELSE
        RAISE EXCEPTION 'Invalid object name format. Expected format: [schema].[object_name]';
    END IF;
    IF target_object_name LIKE '%.%' THEN
        target_schema := split_part(target_object_name, '.', 1);
        target_object := split_part(target_object_name, '.', 2);
    ELSE
        RAISE EXCEPTION 'Invalid object name format. Expected format: [schema].[object_name]';
    END IF;
    nowdate := now();
    SELECT type INTO object_type FROM (
        SELECT DISTINCT CASE 
                            WHEN c.relkind = 'r' or 'p' THEN 'TABLE'
                            WHEN c.relkind = 'v' THEN 'VIEW'
                            WHEN c.relkind = 'm' THEN 'MVIEW'
                            WHEN c.relkind = 's' THEN 'SEQUENCE'
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
        query := format('CREATE OR REPLACE VIEW %I.%I AS SELECT * FROM %I.%I;', target_schema, target_object, source_schema, source_object);
        EXECUTE query;
        SELECT string_agg(column_name, ', ')
        INTO column_list
        FROM information_schema.columns
        WHERE table_schema = source_schema 
            AND table_name = source_object;
        
        INSERT INTO pgsynonym.pgsynonym_info VALUES(
            target_schema,
            target_object,
            source_schema,
            source_object,
            object_type,
            column_list,
            nowdate,
            'VALID',
            ''
        );
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
                query := format('CREATE OR REPLACE PROCEDURE %I.%I(%s) LANGUAGE plpgsql AS $func$ BEGIN CALL %I.%I(%s); END; $func$;', target_schema, target_object, rec.argument_data_types, source_schema, source_object, param_list);
            ELSIF object_type = 'FUNCTION' THEN
                query := format('CREATE OR REPLACE FUNCTION %I.%I(%s) RETURNS %s AS $func$ BEGIN RETURN %I.%I(%s); END; $func$ LANGUAGE plpgsql;', target_schema, target_object, rec.argument_data_types, rec.result_data_type, source_schema, source_object, param_list);
            ELSE
                RAISE EXCEPTION 'Object does not exist or is not a supported type.';
            END IF;
            EXECUTE query;
            INSERT INTO pgsynonym.pgsynonym_info VALUES(
                target_schema,
                target_object,
                source_schema,
                source_object,
                object_type,
                param_list,
                nowdate,
                'VALID',
                ''
            );
        END LOOP;
    END IF;
    RETURN 'SYNONYM ' || object_type || ' CREATED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- PGSYNONYM DROP
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_drop(pgsynonym_name TEXT)
RETURNS TEXT AS $$
DECLARE
    pgsynonym_schema text;
    pgsynonym_object text;
    rec record;
    query text;
    param_list text;
    arr_length int;
    i int;
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;
    
    IF pgsynonym_name LIKE '%.%' THEN
        pgsynonym_schema := split_part(pgsynonym_name, '.', 1);
        pgsynonym_object := split_part(pgsynonym_name, '.', 2);
    ELSE
        RAISE EXCEPTION 'Invalid object name format. Expected format: [schema].[object_name]';
    END IF;

    FOR rec IN
        SELECT * 
        FROM pgsynonym.pgsynonym_info 
        WHERE synonym_name = pgsynonym_object AND synonym_schema = pgsynonym_schema
    LOOP
        IF rec.origin_type IS NULL THEN
            RAISE EXCEPTION 'Object does not exist or is not a supported type.';
        END IF;

        IF rec.origin_type = 'TABLE' THEN
            query := format('DROP VIEW %I.%I;', pgsynonym_schema, pgsynonym_object);
            EXECUTE query;
        ELSE
            FOR rec IN
                SELECT 
                    pg_catalog.pg_get_function_result(p.oid) as "result_data_type",
                    pg_catalog.pg_get_function_arguments(p.oid) as "argument_data_types"
                FROM pg_catalog.pg_proc p
                    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = pgsynonym_schema
                    AND p.proname = pgsynonym_object
                    AND pg_catalog.pg_function_is_visible(p.oid)
                    AND n.nspname <> 'pg_catalog'
                    AND n.nspname <> 'information_schema'
            LOOP
                IF rec.origin_type = 'PROCEDURE' THEN
                    query := format('DROP PROCEDURE %I.%I(%s);', pgsynonym_schema, pgsynonym_object, rec.argument_data_types);
                ELSIF rec.origin_type = 'FUNCTION' THEN
                    query := format('DROP FUNCTION %I.%I(%s);', pgsynonym_schema, pgsynonym_object, rec.argument_data_types);
                ELSE
                    RAISE EXCEPTION 'Object does not exist or is not a pgsynonym object.';
                END IF;
                EXECUTE query;
            END LOOP;
        END IF;
    END LOOP;
    DELETE FROM pgsynonym.pgsynonym_info WHERE synonym_schema = pgsynonym_schema AND synonym_name = pgsynonym_object;
    RETURN 'PGSYNONYM ' || pgsynonym_object || ' DROPED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- PGSYNONYM complie
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_complie(pgsynonym_name text)
RETURNS TEXT AS $$
DECLARE
    origin_schema text;
    origin_name text;
    input_name text;
    delete_target text;
    rec record;
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;

    IF pgsynonym_name LIKE '%.%' THEN
        pgsynonym_schema := split_part(pgsynonym_name, '.', 1);
        pgsynonym_object := split_part(pgsynonym_name, '.', 2);
    ELSE
        RAISE EXCEPTION 'Invalid object name format. Expected format: [schema].[object_name]';
    END IF;

    IF pgsynonym_name IN ('all', 'ALL', '*') THEN
        FOR rec IN 
            SELECT synonym_name, origin_object_schema, origin_object 
            FROM pgsynonym.pgsynonym_info 
        LOOP
            input_name := rec.origin_object_schema || '.' || rec.origin_object;
            delete_target := pgsynonym_schema||'.'||pgsynonym_object
            PERFORM pgsynonym_drop(delete_target);
            PERFORM pgsynonym_create(input_name, delete_target);
        END LOOP;
    ELSE
        SELECT origin_object_schema, origin_object 
        INTO origin_schema, origin_name 
        FROM pgsynonym.pgsynonym_info
        WHERE synonym_name = pgsynonym_name;

        input_name := origin_schema || '.' || origin_name;

        PERFORM pgsynonym_drop(pgsynonym_name);
        PERFORM pgsynonym_create(input_name, pgsynonym_name);
    END IF;
    RETURN 'PGSYNONYM REFRESHED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- PGSYNONYM SHOW
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_show()
RETURNS TABLE(
    synonym_schema text,
    synonym_name text,
    origin_object_schema text,
    origin_object text,
    origin_type text,
    attributes text,
    creation_date timestamp,
    status text,
    comments text
) AS $$
DECLARE
    rec pgsynonym.pgsynonym_info%ROWTYPE;
    column_list TEXT;
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;
    FOR rec IN SELECT * FROM pgsynonym.pgsynonym_info LOOP
        SELECT string_agg(column_name, ', ') INTO column_list
        FROM information_schema.columns
        WHERE table_schema = rec.origin_object_schema
        AND table_name = rec.origin_object;

        IF column_list = rec.attributes THEN
            UPDATE pgsynonym.pgsynonym_info
            SET status = 'VALID'
            WHERE pgsynonym.pgsynonym_info.synonym_name = rec.synonym_name; 
        ELSE
            UPDATE pgsynonym.pgsynonym_info
            SET status = 'INVALID'
            WHERE pgsynonym.pgsynonym_info.synonym_name = rec.synonym_name;
        END IF;
    END LOOP;

    RETURN QUERY SELECT * FROM pgsynonym.pgsynonym_info;
END;
$$ LANGUAGE plpgsql;

-- GRANT PRIVILEGES
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_grant(user_name TEXT, target_synonym TEXT, privileges TEXT)
RETURNS TEXT as $$
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;
    IF user_name = 'public' THEN
    EXECUTE 'GRANT ' || privileges || ' ON pgsynonym.' || target_synonym || ' TO ' || user_name || ';';
    EXECUTE 'GRANT USAGE ON SCHEMA pgsynonym TO ' || user_name || ';';
    EXECUTE 'ALTER ROLE '||quote_ident(user_name)||' SET search_path = pgsynonym, "$user", public';
    RETURN 'SYNONYM GRANTED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;

-- REVOKE PRIVILEGES
CREATE OR REPLACE FUNCTION pgsynonym.pgsynonym_revoke(user_name TEXT, target_synonym TEXT, privileges TEXT)
RETURNS TEXT as $$
BEGIN
    IF current_user <> 'pgsynonym' THEN
        RAISE EXCEPTION 'Permission denied. This function can only be executed by the user "pgsynonym".';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'The current user must be a superuser.';
    END IF;
    EXECUTE 'REVOKE ' || privileges || ' ON pgsynonym.' || target_synonym || ' FROM ' || user_name || ';';
    EXECUTE 'REVOKE USAGE ON SCHEMA pgsynonym FROM ' || user_name || ';';
    EXECUTE 'ALTER ROLE '||quote_ident(user_name)||' SET search_path = "$user", public';
    RETURN 'SYNONYM REVOKED SUCCESSFULLY';
END;
$$ LANGUAGE plpgsql;
