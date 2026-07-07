-------------------------------------------------------------------------------
-- concurrent_req_cancel.sql
-------------------------------------------------------------------------------
-- PL/SQL to cancel queued up concurrent requests via API
-------------------------------------------------------------------------------
-- Date         Author   Change
-- 19-OCT-2022  vseeram  Created
-------------------------------------------------------------------------------

SET SERVEROUTPUT ON

DECLARE
    CURSOR c_prog IS -- (p_user_id NUMBER) IS
    SELECT DISTINCT
        request_id
    FROM
        fnd_concurrent_requests
    WHERE
        concurrent_program_id IN (
            SELECT
                concurrent_program_id
            FROM
                fnd_concurrent_programs_tl
            WHERE
                user_concurrent_program_name = 'Prepayments Matching Program'
        )
--    AND request_id = 21976345 -- uncomment and manually set request_id to cancel
--    AND requested_by = p_user_id
    ORDER BY
        1;

    CURSOR c_user_id IS
    SELECT
        requested_by user_id
    FROM
        fnd_concurrent_requests
    WHERE
        concurrent_program_id IN (
            SELECT
                concurrent_program_id
            FROM
                fnd_concurrent_programs_tl
            WHERE
                user_concurrent_program_name = 'Prepayments Matching Program'
        )
    ORDER BY
        1;

    lv_message                          VARCHAR2(300);
    lb_result                           BOOLEAN := NULL;
    lv_result                           VARCHAR2(5);

    ----------------------------------------------------------------------------
    -- call apps_initialize before running pl/sql
    ----------------------------------------------------------------------------
    PROCEDURE initialize IS
        l_user_id           fnd_user_resp_groups.user_id%TYPE;
        l_responsibility_id fnd_user_resp_groups.responsibility_id%TYPE;
        l_application_id    fnd_user_resp_groups.responsibility_application_id%TYPE;
        l_security_group_id fnd_user_resp_groups.security_group_id%TYPE;
    BEGIN
        SELECT
            furg.user_id,
            furg.responsibility_id,
            furg.responsibility_application_id,
            furg.security_group_id
        INTO
            l_user_id,
            l_responsibility_id,
            l_application_id,
            l_security_group_id
        FROM
            fnd_user_resp_groups furg
        WHERE
                1 = 1
            AND furg.user_id = (
                SELECT
                    user_id
                FROM
                    fnd_user
                WHERE
                    user_name = 'SYSADMIN'
            )
            AND furg.responsibility_id = (
                SELECT
                    responsibility_id
                FROM
                    fnd_responsibility_vl
                WHERE
                    responsibility_name = 'System Administrator'
            );

        fnd_global.apps_initialize(l_user_id, l_responsibility_id, l_application_id);
    END initialize;


BEGIN
    initialize;
    FOR x IN c_prog LOOP
        dbms_output.put_line('Updating request_id: ' || to_char(x.request_id));
        UPDATE fnd_concurrent_requests
        SET
            phase_code = 'C',
            status_code = 'D',
            completion_text = 'Cancelled via SQL',
            last_update_date = sysdate,
            last_updated_by = fnd_global.user_id
        WHERE
            request_id = x.request_id;
/*
    lb_result := fnd_concurrent.cancel_request(request_id => x.request_id, message => lv_message);
    IF lb_result = TRUE THEN
      lv_result := 'TRUE';
    ELSE
      lv_result := 'FALSE';
    END IF;
    dbms_output.put_line('request_id: ' || To_Char(x.request_id) || ', lv_result: ' || lv_result || ', lv_message: ' || lv_message);
*/
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line(sqlcode || ': ' || sqlerrm);
END;
/