--------------------------------------------------------------------------------
-- email_preference_set.sql
--------------------------------------------------------------------------------
-- This script sets the email preference for all EBS users to MAILHTML.
--------------------------------------------------------------------------------
-- Date         Author   Change
-- 22-JUN-2020  vseeram  Created
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
DECLARE
  CURSOR c_users IS
  SELECT
    fu.user_name
  FROM
    fnd_user fu
  WHERE
    1 = 1
  AND fu.employee_id IN (
    SELECT DISTINCT
      papf.person_id
    FROM
      per_all_people_f papf
    WHERE
      1 = 1
  )
  ORDER BY
    fu.user_name;

  ln_counter                            PLS_INTEGER := 0;
  lv_commit                             VARCHAR2(255) := Upper(NVL('&commit_flag', 'N'));
  
BEGIN
    FOR x1 IN c_users
    LOOP
        ln_counter := ln_counter + 1;
        dbms_output.put_line(ln_counter || '. Setting email preference for ' || x1.user_name);
        FND_PREFERENCE.put(x1.user_name, 'WF', 'MAILTYPE', 'MAILHTML');
    END LOOP;
    IF lv_commit = 'Y' THEN
        dbms_output.put_line('Committing...');
        COMMIT;
    ELSE
        dbms_output.put_line('Rolling back...');
        ROLLBACK;
    END IF; 
END;
/

