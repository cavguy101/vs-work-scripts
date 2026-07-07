--------------------------------------------------------------------------------
-- scan_for_new_datafiles.sql
--------------------------------------------------------------------------------
-- Check the database for tablespaces over 90% filled and generates a SQL
-- statement to add another datafile.
--------------------------------------------------------------------------------
-- Assume that the datafile filenames are of the format filenameXX.ext
-- where XX are digits. The script will try to extract the XX, and increase
-- it by 1 to get the new filename.
--------------------------------------------------------------------------------
-- Run validate_datafiles.sql to resolve any naming issues of datafiles.
--------------------------------------------------------------------------------
-- 09-APR-2026  vseeram  Created
--------------------------------------------------------------------------------
SET TRIMSPOOL ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE 1000000


DECLARE
    -- get list of all tablespace and percent free
    CURSOR c_tablespaces IS
    SELECT DISTINCT
        nvl(b.tablespace_name,nvl(fs.tablespace_name,'UNKOWN') ) name,
        kbytes_alloc   kbytes,
        kbytes_alloc - nvl(kbytes_free,0) used,
        nvl(kbytes_free,0) free,
        Round( ( kbytes_alloc - nvl(kbytes_free,0) ) / kbytes_alloc, 4 ) * 100 pct_used,
        nvl(largest,0) largest
    FROM
        (
            SELECT
                SUM(bytes) / 1024 kbytes_free,
                MAX(bytes) / 1024 largest,
                tablespace_name
            FROM
                sys.dba_free_space
            GROUP BY
                tablespace_name
        ) fs,
        (
            SELECT
                SUM(bytes) / 1024 kbytes_alloc,
                tablespace_name
            FROM
                sys.dba_data_files
            GROUP BY
                tablespace_name
        ) b
    WHERE
        fs.tablespace_name (+) = b.tablespace_name
    AND ((( kbytes_alloc - nvl(kbytes_free,0) ) / kbytes_alloc ) * 100) > 90
    ORDER BY
        1
    ;

    -- get all filenames for tablespace p_tablespace_name
    CURSOR c_filename(p_tablespace_name VARCHAR2) IS
    SELECT 
        file_name, 
        bytes/1024/1024 mb
    FROM
        dba_data_files
    WHERE
        tablespace_name = p_tablespace_name
    ORDER BY 
        1;

    -- get the last datafile for a tablespace (order by name in desc order)
    CURSOR c_last_filename(p_tablespace_name VARCHAR2) IS
    SELECT
        file_name,
        mb
    FROM (
        SELECT
            file_name,
            bytes/1024/1024 mb
        FROM
            sys.dba_data_files
        WHERE
            tablespace_name = p_tablespace_name
        ORDER BY
            1 DESC
    )
    WHERE 
        ROWNUM = 1
    ;


    ----------------------------------------------------------------------------
    -- is_numeric - return true if parameter is a number
    ----------------------------------------------------------------------------
    FUNCTION is_numeric(p_number IN VARCHAR2) RETURN BOOLEAN IS
        lv_new_num                      NUMBER;
    BEGIN
        lv_new_num := To_Number(p_number);
        RETURN TRUE;
    EXCEPTION
        WHEN value_error THEN
            RETURN FALSE;
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in is_numeric:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END is_numeric;


    ----------------------------------------------------------------------------
    -- print out all datafiles in tablespace p_tablespace_name
    ----------------------------------------------------------------------------
    PROCEDURE p000_list_filenames(p_tablespace_name IN VARCHAR2) IS
    BEGIN
        FOR f IN c_filename(p_tablespace_name) LOOP
            dbms_output.put_line('    ' || f.file_name || ':  ' || f.mb || ' MB');
        END LOOP;
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p000_list_filenames:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END;
    
    
    ----------------------------------------------------------------------------
    -- given a filename, parse it into extension, leading part and number
    ----------------------------------------------------------------------------
    PROCEDURE p010_parse_filename(p_file_name IN VARCHAR2, p_prefix OUT VARCHAR2, 
        p_value OUT VARCHAR2, p_ext OUT VARCHAR2) IS
        ln_len                          NUMBER := 0;
        ln_posn                         NUMBER := 0;
        ln_end_posn                     NUMBER := 0;
    BEGIN
        ln_len := Length(p_file_name);
        ln_posn := ln_len - 1;
    
        -- get extension first
        WHILE is_numeric(Substr(p_file_name, ln_posn, 1)) = False AND ln_posn > 0 LOOP
            ln_posn := ln_posn - 1;
        END LOOP;
        IF ln_posn > 0 THEN
            p_ext := SubStr(p_file_name, ln_posn + 1, ln_len - ln_posn + 1);
        END IF;

        -- dispay value at ln_posn (for debugging purposes)
        -- dbms_output.put_line('ln_posn: ' || SubStr(p_file_name, ln_posn, 1));

        -- extract over numeric part
        ln_end_posn := ln_posn;
        WHILE is_numeric(Substr(p_file_name, ln_posn, 1)) = True AND ln_posn > 0 LOOP
            ln_posn := ln_posn - 1;
        END LOOP;
        p_value := SubStr(p_file_name, ln_posn + 1, ln_end_posn - ln_posn);
        
        -- get path and filename
        p_prefix := SubStr(p_file_name, 1, ln_posn);

        -- print all parts of the filename
        dbms_output.put_line('    Path: ' || p_prefix);
        dbms_output.put_line('    Value: ' || p_value);
        dbms_output.put_line('    Extension: ' || p_ext);

        -- check if value is invalid
        IF Is_Numeric(p_value) = False THEN
            dbms_output.put_line('No number in : ' || p_file_name);
        END IF;            
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p010_parse_filename:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p010_parse_filename;


    ----------------------------------------------------------------------------
    -- print sql statement to alter the datafile filename
    ----------------------------------------------------------------------------
    PROCEDURE p020_display_filenames(p_tablespace_name IN VARCHAR2) IS
    BEGIN
        dbms_output.put_line('FILE_NAME');
        dbms_output.put_line(LPad('-', 40, '-'));
        FOR x IN c_filename(p_tablespace_name) LOOP
            dbms_output.put_line(x.file_name || '  ' || x.mb || ' MB');
        END LOOP;
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p020_display_filenames:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p020_display_filenames;


    ----------------------------------------------------------------------------
    -- print ALTER sql statement to add a new datafile
    ----------------------------------------------------------------------------
    PROCEDURE p025_print_alter_stmt(p_tablespace_name IN VARCHAR2, 
        p_filename IN VARCHAR2, p_size IN NUMBER) IS
    BEGIN
        dbms_output.new_line;
        dbms_output.put_line('ALTER TABLESPACE ' || p_tablespace_name || ' ADD DATAFILE ''' || p_filename || ''' SIZE ' || p_size || 'M;');
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p025_print_alter_stmt:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p025_print_alter_stmt;


    ----------------------------------------------------------------------------
    -- validate each filename in tablespace against the first filename
    ----------------------------------------------------------------------------
    PROCEDURE p030_validate_filenames(p_tablespace_name IN VARCHAR2, 
        p_prefix IN VARCHAR2, p_value IN VARCHAR2, p_ext IN VARCHAR2, p_size IN NUMBER) IS
        ln_value                        NUMBER := To_Number(p_value);
        lv_expected                     VARCHAR2(255) := NULL;
    BEGIN
        lv_expected := p_prefix || LPad(To_Char(ln_value + 1), 2, '0') || p_ext;
        p025_print_alter_stmt(p_tablespace_name, lv_expected, p_size);
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p030_validate_filenames:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p030_validate_filenames;


    ----------------------------------------------------------------------------
    -- process each tablespace: parse the filename for the first datafile,
    -- display all filenames for the tablespace and then validate the filenames
    ----------------------------------------------------------------------------
    PROCEDURE p040_process_tablespace(p_tablespace_name IN VARCHAR2, 
        p_file_name IN VARCHAR2, p_size IN NUMBER) IS
        lv_path                         VARCHAR2(255) := NULL;
        lv_value                        VARCHAR2(255) := NULL;
        lv_ext                          VARCHAR2(255) := NULL;
    BEGIN
        p010_parse_filename(p_file_name, lv_path, lv_value, lv_ext);
        p020_display_filenames(p_tablespace_name);
        p030_validate_filenames(p_tablespace_name, lv_path, lv_value, lv_ext, p_size);
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p040_process_tablespace:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p040_process_tablespace;


-- main driver: process all tablespaces over 90% filled
BEGIN
    FOR x IN c_tablespaces LOOP
        FOR y IN c_last_filename(x.name) LOOP
            dbms_output.new_line;
            dbms_output.put_line('Tablespace ' || x.name || ' (' || x.pct_used|| '% used) :');
            p040_process_tablespace(x.name, y.file_name, y.mb);
        END LOOP;
    END LOOP;    
END;
/
