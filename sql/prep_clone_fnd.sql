--------------------------------------------------------------------------------
-- prep_clone_fnd.sql
--------------------------------------------------------------------------------
-- Preps a new clone of EBS
-- 1. Set the system profiles beginning with 'Signon Password' to null at the
-- Site level.
--------------------------------------------------------------------------------
-- Run this script in SQL Developer using Run Script (F5), to view output
--------------------------------------------------------------------------------
-- Ver Date         Author   Change
-- 1   10-JUL-2018  vseeram  Created (forked from prep_new_clone.sql)
-- 2   07-AUG-2020  vseeram  Added code to 
--------------------------------------------------------------------------------

COL LONG_NAME FORMAT A50
COL SHORT_NAME FORMAT A50
COL LEVEL FORMAT A10
COL LEVEL_VALUE FORMAT A10
COL PROFILE_VALUE FORMAT A50
COL UPDATED_BY FORMAT A20

SET FEEDBACK OFF
SET SERVEROUTPUT ON SIZE 1000000

DECLARE
    CURSOR profile_cur IS
    SELECT
        a.profile_option_name
    FROM
        apps.fnd_profile_options a
    WHERE
            1 = 1
        AND ( a.profile_option_name LIKE 'SIGN%'
              OR a.profile_option_name = 'DIAGNOSTICS'
              OR a.profile_option_name = 'FND_HIDE_DIAGNOSTICS'
              OR a.profile_option_name = 'ICX_SESSION_TIMEOUT'
              OR a.profile_option_name = 'ICX_LIMIT_TIME' );
  
    /* variables */
    lc_name        VARCHAR2(100) := 'EBSPROD';
    lv_profile     fnd_profile_options.profile_option_name%TYPE;
    lv_name        VARCHAR2(100);
    lv_value       VARCHAR2(2000);
    lv_saved       BOOLEAN;
    v_resp_appl_id NUMBER;
    v_resp_id      NUMBER;
    v_user_id      NUMBER;

    /* list of profiles to change, and values to change to */
    TYPE profileoptions IS VARRAY(24) OF VARCHAR2(255);
    lv_profiles    profileoptions := profileoptions('SIGNON_PASSWORD_CASE', '', 
        'SIGNON_PASSWORD_CUSTOM', '', 'SIGNON_PASSWORD_FAILURE_LIMIT', '', 
        'SIGNON_PASSWORD_HARD_TO_GUESS', '', 'SIGNON_PASSWORD_LENGTH', '',
        'SIGNON_PASSWORD_NO_REUSE', '', 'DIAGNOSTICS', 'Y', 
        'FND_HIDE_DIAGNOSTICS', 'N', 'SIGNONAUDIT:NOTIFY', 'N', 
        'SIGNONAUDIT:LEVEL', 'D', 'ICX_SESSION_TIMEOUT', '1440', 'ICX_LIMIT_TIME', '24');


    /* given a profile option name, get value to update profile option to */
    FUNCTION get_value (
        p_profile_name IN VARCHAR2
    ) RETURN VARCHAR2 IS
        i NUMBER;
    BEGIN
        FOR i IN 1..lv_profiles.count - 1 LOOP
            IF lv_profiles(i) = p_profile_name THEN
                RETURN lv_profiles(i + 1);
            END IF;
        END LOOP;

        RETURN NULL;
    END;

BEGIN
    /* initialize session */
    v_resp_appl_id := fnd_global.resp_appl_id;
    v_resp_id := fnd_global.resp_id;
    v_user_id := fnd_global.user_id;
    fnd_global.apps_initialize(v_user_id, v_resp_id, v_resp_appl_id);

    /* check instance name, and if EBSPROD, then raise exception */
    SELECT
        name
    INTO lv_name
    FROM
        v$database;

    IF lv_name = lc_name THEN
        raise_application_error(-20001, 'Database ' || lc_name || ' detected, stopping script');
    END IF;

    /* print profiles before update */
    dbms_output.put_line(chr(10) || 'Values before update' || chr(10) || '--------------------');

    FOR l_profile_name IN profile_cur LOOP
        lv_value := fnd_profile.value(l_profile_name.profile_option_name);
        dbms_output.put_line('Profile Name: ' || l_profile_name.profile_option_name || ', Value: ' || lv_value);
    END LOOP;

    dbms_output.put_line('');
  
    /* update profiles at Site level */
    FOR l_profile_name IN profile_cur LOOP
        lv_saved := fnd_profile.save(x_name => l_profile_name.profile_option_name, 
            x_value => get_value(l_profile_name.profile_option_name), 
            x_level_name => 'SITE', 
            x_level_value => NULL, 
            x_level_value_app_id => NULL, 
            x_level_value2 => NULL);
        IF lv_saved = true THEN
            dbms_output.put_line(l_profile_name.profile_option_name || ' Updated');
        ELSE
            dbms_output.put_line(l_profile_name.profile_option_name || ' Not Updated');
        END IF;
    END LOOP;

    COMMIT;

    /* print profiles after update */
    dbms_output.put_line(chr(10) || 'Values after update' || chr(10) || '-------------------');

    FOR l_profile_name IN profile_cur LOOP
        lv_value := fnd_profile.value(l_profile_name.profile_option_name);
        dbms_output.put_line('Profile Name: ' || l_profile_name.profile_option_name || ', Value: ' || lv_value);
    END LOOP;

    dbms_output.put_line('Finished modifying profiles' || chr(10) || sqlerrm);
EXCEPTION
    WHEN OTHERS THEN
--  dbms_output.put_line ('Error modifying profile name ' || l_profile_name.profile_option_name || chr(10) || sqlerrm);
        dbms_output.put_line('Error modifying profile name ' || chr(10) || sqlerrm);
END;
/


-------------------------------------------------------------------------------
-- 3. Schedule the "Gather Schema Statistics" concurrent program to run every night
-- https://oracleappsdna.com/2013/06/plsql-script-to-submit-a-concurrent-request-from-backend/
-------------------------------------------------------------------------------
SET SERVEROUTPUT ON

DECLARE
    c_responsibility_name    VARCHAR2(255) := 'System Administrator';
    c_user_name              VARCHAR2(255) := 'SYSADMIN';
    c_application_short_name VARCHAR2(255) := 'FND';
    c_program_short_name     VARCHAR2(255) := 'FNDGSCST';
    c_description            VARCHAR2(255) := 'Gather Schema Statistics scheduled via API on ' || trunc(sysdate);
    c_argument1              VARCHAR2(255) := 'ALL';
    c_argument2              VARCHAR2(255) := '10';
    c_argument3              VARCHAR2(255) := '';
    c_argument4              VARCHAR2(255) := 'NOBACKUP';
    c_argument5              VARCHAR2(255) := '';
    c_argument6              VARCHAR2(255) := 'LASTRUN';
    c_argument7              VARCHAR2(255) := 'GATHER';
    c_argument8              VARCHAR2(255) := '';
    c_argument9              VARCHAR2(255) := 'Y';
    l_responsibility_id      NUMBER;
    l_application_id         NUMBER;
    l_user_id                NUMBER;
    l_boolean                BOOLEAN;


    PROCEDURE submit_gather_schema IS
        l_request_id NUMBER;
    BEGIN  
        -- Submitting Concurrent Request
        l_request_id := fnd_request.submit_request(application => c_application_short_name, 
            program => c_program_short_name, 
            description => c_description, 
            start_time => trunc(sysdate) + 1,
            sub_request => FALSE,
            argument1 => c_argument1, 
            argument2 => c_argument2, 
            argument3 => c_argument3, 
            argument4 => c_argument4, 
            argument5 => c_argument5,
            argument6 => c_argument6, 
            argument7 => c_argument7, 
            argument8 => c_argument8, 
            argument9 => c_argument9
        );
        COMMIT;

        IF l_request_id = 0 THEN
            dbms_output.put_line('Concurrent request failed to submit');
        ELSE
            dbms_output.put_line('Successfully Submitted the Concurrent Request: ' || c_description);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error While Submitting Concurrent Request ' || to_char(sqlcode) || '-' || sqlerrm);
    END submit_gather_schema;


BEGIN
    -- get responsibility_id and application_id for System Administrator responsibility
    SELECT DISTINCT
        fr.responsibility_id,
        frx.application_id
    INTO
        l_responsibility_id,
        l_application_id
    FROM
        apps.fnd_responsibility    frx,
        apps.fnd_responsibility_tl fr
    WHERE
            fr.responsibility_id = frx.responsibility_id
        AND lower(fr.responsibility_name) LIKE lower(c_responsibility_name);
	
    -- get user_id for SYSADMIN
    SELECT
        user_id
    INTO l_user_id
    FROM
        fnd_user
    WHERE
        user_name = c_user_name;

    -- Set environment context
    apps.fnd_global.apps_initialize(l_user_id, l_responsibility_id, l_application_id);

    -- Submit gather schema statistics to run right away (uncomment below to run)
    -- submit_gather_schema;

    -- set repeat interval = 1 day
--  l_boolean := fnd_submit.set_repeat_options;
    l_boolean := fnd_submit.set_repeat_options(repeat_interval => 1, repeat_unit => 'DAYS', repeat_type => 'START');
  
    -- print status message if setting the repeat options was successful
    IF l_boolean = true THEN
        dbms_output.put_line('Repeat interval set');
    ELSE
        dbms_output.put_line('Repeat interval not set');
    END IF;
  
    -- Schedule gather schema statistics to run based on above schedule
    submit_gather_schema;
EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line('Unexpected error encountered ' || to_char(sqlcode) || '-' || sqlerrm);
END;
/


-------------------------------------------------------------------------------
-- 4. Add functions to navigator hotlist
-- https://oracleappsdna.com/2013/06/plsql-script-to-submit-a-concurrent-request-from-backend/
-------------------------------------------------------------------------------
SET SERVEROUTPUT ON

DECLARE
    PROCEDURE insert_into_desktop_objects (
        p_func_name     IN VARCHAR2,
        p_func_sequence IN NUMBER,
        p_user_id       IN NUMBER,
        p_resp_id       IN NUMBER,
        p_appl_id       IN NUMBER,
        p_login_id      IN NUMBER
    ) IS
        ln_count NUMBER := 0;
    BEGIN
        SELECT
            COUNT(*)
        INTO ln_count
        FROM
            fnd_user_desktop_objects fudo
        WHERE
                1 = 1
            AND fudo.user_id = p_user_id
            AND fudo.responsibility_id = p_resp_id
            AND fudo.application_id = p_appl_id
            AND fudo.function_name = p_func_name;

        IF ln_count = 0 THEN
            INSERT INTO fnd_user_desktop_objects (
                desktop_object_id,
                user_id,
                application_id,
                responsibility_id,
                object_name,
                function_name,
                object_label,
                parameter_string,
                sequence,
                last_update_date,
                last_updated_by,
                creation_date,
                created_by,
                last_update_login,
                type
            )
                SELECT
                    fnd_desktop_object_id_s.NEXTVAL,
                    p_user_id,
                    p_appl_id,
                    p_resp_id,
                    'FUNCTION',
                    p_func_name,
                    'FUNCTION',
                    '',
                    p_func_sequence,
                    sysdate,
                    p_user_id,
                    sysdate,
                    p_user_id,
                    p_login_id,
                    'FUNCTION'
                FROM
                    sys.dual;

            dbms_output.put_line('Inserted function ' || p_func_name || ' into navigator hotlist.');
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error encountered: ' || sqlcode || ': ' || sqlerrm);
            ROLLBACK;
    END insert_into_desktop_objects;

BEGIN
    insert_into_desktop_objects(p_func_name => 'PERWSHRG-403', p_func_sequence => 1, p_user_id => 0, p_resp_id => 21538, p_appl_id => 800, p_login_id => 0);

    insert_into_desktop_objects(p_func_name => 'PAYWSACT-329', p_func_sequence => 2, p_user_id => 0, p_resp_id => 21538, p_appl_id => 800, p_login_id => 0);

    insert_into_desktop_objects(p_func_name => 'PAYWSACT-328', p_func_sequence => 3, p_user_id => 0, p_resp_id => 21538, p_appl_id => 800, p_login_id => 0);

END;
/