--------------------------------------------------------------------------------
-- column_value_find.sql
--
-- This script finds the location of a particular value in the database.
-- It scans all tables whose column name have a particular substring.
-- Then it scans that column for the value.
-- n.b. Response time will depend on wildcards used and no. of rows processed
--------------------------------------------------------------------------------

SET TIMING ON
SET SERVEROUTPUT ON
DECLARE

    TYPE parameters_tab IS TABLE OF VARCHAR2(255);
    
    /* parameters are: owner, table_name, column_name, value, column type */
    parameter_name parameters_tab := parameters_tab('%', 'FND%', '%', 'SYSADMIN', 'VARCHAR2'); 

    c_owner                             CONSTANT VARCHAR2(255) := parameter_name(1);
    c_table_name                        CONSTANT VARCHAR2(255) := parameter_name(2);
    c_column_name                       CONSTANT VARCHAR2(255) := parameter_name(3);
    c_value                             CONSTANT VARCHAR2(255) := parameter_name(4);
    c_datatype                          CONSTANT VARCHAR2(255) := parameter_name(5);

    c_showsql_flag                      CONSTANT BOOLEAN := FALSE;
    c_showvalues_flag                   CONSTANT BOOLEAN := TRUE;

    CURSOR c1 IS
    SELECT
        dtc.owner,
        dtc.table_name,
        dtc.column_name
    FROM
        dba_tab_cols dtc
    WHERE
        1 = 1
        AND dtc.owner LIKE c_owner
        AND dtc.table_name LIKE c_table_name
        AND dtc.column_name LIKE c_column_name
        AND dtc.data_type = c_datatype
        AND dtc.column_name NOT LIKE '%:%'
        AND dtc.column_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM dba_tables dt WHERE dt.table_name = dtc.table_name AND
            dt.tablespace_name IS NOT NULL
        );

    TYPE values_t IS TABLE OF VARCHAR2(32767);
    l_values                            values_t;
   
    lv_query                            VARCHAR2(255);
    ln_row_count                        NUMBER;
    ln_loop_count                       NUMBER := 0;
    ln_found_count                      NUMBER := 0;
    
BEGIN
    FOR x IN c1 
    LOOP
        ln_loop_count := ln_loop_count + 1;
        lv_query := 'SELECT COUNT(*) FROM ' || x.owner || '.' || x.table_name || ' WHERE "' || x.column_name || '" LIKE ''' || c_value || '''';
		
        IF c_showsql_flag THEN
            dbms_output.put_line(lv_query);
        END IF;
		
        EXECUTE IMMEDIATE(lv_query) INTO ln_row_count;
		
        IF ln_row_count > 0 THEN
            ln_found_count := ln_found_count + 1;
            dbms_output.put_line(ln_row_count || ' row(s) found in ' || lv_query);
            lv_query := 'SELECT DISTINCT ' || x.column_name || ' FROM ' || x.owner || '.' || x.table_name || ' WHERE "' || x.column_name || '" LIKE ''' || c_value || '''';
            dbms_output.put_line('Executing: ' || lv_query);
            EXECUTE IMMEDIATE(lv_query) BULK COLLECT INTO l_values;
			
            IF c_showvalues_flag THEN
                FOR indx IN 1 .. l_values.COUNT
                LOOP 
                    dbms_output.put_line('    Value found: ' || l_values (indx));
                END LOOP;
            END IF;
        END IF;
    END LOOP;    

    IF ln_found_count = 0 THEN
        dbms_output.put_line('Search string "' || c_value || '" not found.');
    END IF;
    dbms_output.put_line(Chr(13) || Chr(10) || 'Summary:');
    dbms_output.put_line(ln_loop_count || ' rows processed.');
    dbms_output.put_line(ln_found_count || ' rows found.');

EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line('Error at counter ' || ln_loop_count);
        dbms_output.put_line('Statement being executed: ' || lv_query);
        dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
END;
/
