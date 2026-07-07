--------------------------------------------------------------------------------
-- reset_ebs_password.sql
--------------------------------------------------------------------------------
-- To change/reset password of a user from backend (via the API)
-- https://www.oracleappsdna.com/2016/12/plsql-script-to-reset-user-password-from-backend/
--------------------------------------------------------------------------------
-- 21-JUL-2020  vseeram
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON;

DECLARE
    lv_user_name    VARCHAR2(30) := upper('SYSADMIN');
    lv_new_password VARCHAR2(30) := 'welcome';
    lv_status       BOOLEAN;
BEGIN
    lv_status := fnd_user_pkg.changepassword(username => lv_user_name, newpassword => lv_new_password);
    IF lv_status THEN
        dbms_output.put_line('The password was reset successfully for user ' || lv_user_name);
        COMMIT;
    ELSE
        dbms_output.put_line('Unable to reset password due to ' || sqlcode || ' ' || substr(sqlerrm, 1, 100));
        ROLLBACK;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line('Error encountered: ' || sqlcode || ' ' || sqlerrm);
END;
/
