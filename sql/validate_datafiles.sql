--------------------------------------------------------------------------------
-- validate_datafiles.sql
--------------------------------------------------------------------------------
-- Ensure that datafiles are named consistently for each tablespace.
-- It was observed that some datafiles were not correctly mamed. This 
-- script generates SQL to fix these filenames, so they are consistent.
--------------------------------------------------------------------------------
-- Assume that the first datafile for each tablespace is named correctly, and
-- ensure that each succeeding datafile is named in the same pattern.
-- Assume that the filename is of the format filenameXX.ext. That is, there
-- are a number of letters, followed by digits, followed by an extension.
--------------------------------------------------------------------------------
-- 09-APR-2026  vseeram  Created
--------------------------------------------------------------------------------
SET TRIMSPOOL ON
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING ON
SET SERVEROUTPUT ON SIZE 1000000

DECLARE
    -- get list of all tablespaces with more than one datafile
    CURSOR c_tablespaces IS
    SELECT
        tablespace_name
    FROM
        sys.dba_data_files
    GROUP BY 
        tablespace_name
    HAVING
        Count(*) > 1
    ORDER BY
        1
    ;

    -- get the first datafile for a tablespace
    CURSOR c_first_filename(p_tablespace_name VARCHAR2) IS
    SELECT
        file_name
    FROM (
        SELECT
            file_name
        FROM
            sys.dba_data_files
        WHERE
            tablespace_name = p_tablespace_name
        ORDER BY
            1
    )
    WHERE 
        ROWNUM = 1
    ;
    
    -- get all filenames for tablespace p_tablespace_name
    CURSOR c_filenames(p_tablespace_name VARCHAR2) IS
    SELECT
        file_name
    FROM 
        sys.dba_data_files
    WHERE
        tablespace_name = p_tablespace_name
    ORDER BY
        1
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
        ELSIF To_Number(p_value) != 1 THEN
            dbms_output.put_line('Invalid number first datafile : ' || p_file_name);
        END IF;            
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p010_parse_filename:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p010_parse_filename;


    ----------------------------------------------------------------------------
    -- print all datafiles in tablespace p_tablespace_name
    ----------------------------------------------------------------------------
    PROCEDURE p020_display_filenames(p_tablespace_name IN VARCHAR2) IS
    BEGIN
        dbms_output.put_line('FILE_NAME');
        dbms_output.put_line(LPad('-', 40, '-'));
        FOR x IN c_filenames(p_tablespace_name) LOOP
            dbms_output.put_line(x.file_name);
        END LOOP;
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p020_display_filenames:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p020_display_filenames;
    

    ----------------------------------------------------------------------------
    -- print ALTER sql statement to add a new datafile
    ----------------------------------------------------------------------------
    PROCEDURE p025_print_alter_stmt(p_old_filename IN VARCHAR2, p_new_filename IN VARCHAR2) IS
    BEGIN
        dbms_output.new_line;
        dbms_output.put_line('ALTER DATABASE MOVE DATAFILE ''' || p_old_filename || ''' TO ''' || p_new_filename || ''';');
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p025_print_alter_stmt:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p025_print_alter_stmt;


    ----------------------------------------------------------------------------
    -- verify each filename for a tablespace against the first filename
    ----------------------------------------------------------------------------
    PROCEDURE p030_validate_filenames(p_tablespace_name IN VARCHAR2, 
        p_prefix IN VARCHAR2, p_value IN VARCHAR2, p_ext IN VARCHAR2) IS
        ln_value                        NUMBER := To_Number(p_value);
        lv_expected                     VARCHAR2(255) := NULL;
        lb_errors_found                 BOOLEAN := FALSE;
    BEGIN
        FOR x IN c_filenames(p_tablespace_name) LOOP
            lv_expected := p_prefix || LPad(To_Char(ln_value), 2, '0') || p_ext;
            IF x.file_name != lv_expected THEN
                lb_errors_found := TRUE;
                dbms_output.new_line;
                dbms_output.put_line('Current filename: ' || x.file_name || ', expected filename: ' || lv_expected);
                p025_print_alter_stmt(x.file_name, lv_expected);
            END IF;
            ln_value := ln_value + 1;
        END LOOP;
        IF lb_errors_found = FALSE THEN 
            dbms_output.put_line('No errors found in ' || p_tablespace_name);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p030_validate_filenames:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p030_validate_filenames;


    ----------------------------------------------------------------------------
    -- process each tablespace: parse the filename for the first datafile,
    -- display all filenames for the tablespace and then validate the filenames
    ----------------------------------------------------------------------------
    PROCEDURE p040_process_tablespace(p_tablespace_name IN VARCHAR2, p_file_name IN VARCHAR2) IS
        lv_path                         VARCHAR2(255) := NULL;
        lv_value                        VARCHAR2(255) := NULL;
        lv_ext                          VARCHAR2(255) := NULL;
    BEGIN
        p010_parse_filename(p_file_name, lv_path, lv_value, lv_ext);
        p020_display_filenames(p_tablespace_name);
        p030_validate_filenames(p_tablespace_name, lv_path, lv_value, lv_ext);        
    EXCEPTION 
        WHEN OTHERS THEN
            dbms_output.put_line('Error occurred in p040_process_tablespace:');
            dbms_output.put_line(SQLCODE || ': ' || SQLERRM);
    END p040_process_tablespace;


-- main driver
BEGIN
    FOR x IN c_tablespaces LOOP
        FOR y IN c_first_filename(x.tablespace_name) LOOP
            dbms_output.new_line;
            dbms_output.put_line('Tablespace name: ' || x.tablespace_name || ', ' || y.file_name);
            p040_process_tablespace(x.tablespace_name, y.file_name);
        END LOOP;
    END LOOP;
END;
/
