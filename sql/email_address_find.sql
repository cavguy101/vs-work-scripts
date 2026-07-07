--------------------------------------------------------------------------------
-- email_address_find.sql
--------------------------------------------------------------------------------
-- This script finds the location of a particular email address in the database.
-- It scans all tables that have a column that contains 'EMAIL' in its name
-- and then scans that column for the email address.
--------------------------------------------------------------------------------
-- 04-MAR-2024    vseeram    Created
--------------------------------------------------------------------------------


SET SERVEROUTPUT ON
DECLARE
    CURSOR c1 IS
    SELECT
        owner,
        table_name,
        column_name
    FROM
        dba_tab_cols
    WHERE
        column_name LIKE '%EMAIL%'
        AND num_distinct > 0
        AND data_type = 'VARCHAR2';


    c_email_address                     CONSTANT VARCHAR2(255) := '%vasudev.seeram@pbs.group%';
    
    TYPE emails_t IS TABLE OF VARCHAR2(255);
    l_email_addresses                   emails_t;
   
    lv_query                            VARCHAR2(255);
    ln_count                            NUMBER;
    lb_found                            BOOLEAN := FALSE;
BEGIN
    FOR x IN c1 
    LOOP
        lv_query := 'SELECT COUNT(*) FROM ' || x.owner || '.' || x.table_name || ' WHERE ' || x.column_name || ' LIKE ''' || c_email_address || '''';
        -- dbms_output.put_line(lv_query);
        EXECUTE IMMEDIATE(lv_query) INTO ln_count;
        IF ln_count > 0 THEN
            lb_found := TRUE;
            dbms_output.put_line(ln_count || ' rows found in ' || lv_query);
            lv_query := 'SELECT ' || x.column_name || ' FROM ' || x.owner || '.' || x.table_name || ' WHERE ' || x.column_name || ' LIKE ''' || c_email_address || '''';
            EXECUTE IMMEDIATE(lv_query) BULK COLLECT INTO l_email_addresses;
            FOR indx IN 1 .. l_email_addresses.COUNT
            LOOP 
                dbms_output.put_line('    Email address found: ' || l_email_addresses (indx));
            END LOOP;
        END IF;
    END LOOP;    
    IF lb_found = FALSE THEN
        dbms_output.put_line('Search string ' || c_email_address || ' not found.');
    END IF;
END;
/