--------------------------------------------------------------------------------
-- ach_csv.sql
--------------------------------------------------------------------------------
-- This script generates the output for the ACH in a CSV file.
--------------------------------------------------------------------------------
-- There are six parameters on the concurrent request (the first three are mandatory):
-- 1. p_payroll_id
-- 2. p_consolidation_set_id
-- 3. p_effective_date
-- 4. p_assignment_set_id
-- 5. p_person_id
-- 6. p_action_type
-------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE 1000000

DECLARE
    CURSOR cur_ach (
        p_payroll_id                    IN NUMBER,
        p_consolidation_set_id          IN NUMBER,
        p_effective_date                IN DATE,
        p_assignment_set_id             IN NUMBER,
        p_person_id                     IN NUMBER,
        p_action_type                   IN VARCHAR2
    ) IS
    SELECT
        last_name,
        first_name,
        emp_no_old,
        amount,
        person_id,
        effective_date,
        account_number,
        bank_short_name,
        rt,
        row_num,
        CASE
            WHEN row_num = '1' THEN
                emp_no_old
            ELSE
                emp_no_old || '-' || to_char(row_num - 1)
        END emp_no
    FROM
        (
            SELECT
                TRIM(substr(last_name, 1, 22))  last_name,
                TRIM(substr(first_name, 1, 22)) first_name,
                emp_no                          emp_no_old,
                TRIM(amount)                    amount,
                person_id,
                effective_date,
                TRIM(account_number)            account_number,
                TRIM(bank_short_name)           bank_short_name,
                rt,
                TO_NUMBER(ROW_NUMBER() OVER(PARTITION BY emp_no ORDER BY emp_no)) row_num
            FROM
                (
                    SELECT
                        *
                    FROM
                        TABLE (xx_pay_methods.get_updated_ach(
                            p_payroll_id => p_payroll_id, 
                            p_consolidation_set_id => p_consolidation_set_id, 
                            p_effective_date => p_effective_date, 
                            p_assignment_set_id => p_assignment_set_id, 
                            p_person_id => p_person_id,
                            p_action_type => p_action_type) 
                        )
                    WHERE
                            1 = 1
                        AND amount <> 0
                    ORDER BY
                        emp_no
                )
        );

    CURSOR cur_dir IS
    SELECT
        directory_path
    FROM
        dba_directories
    WHERE
            1 = 1
        AND directory_name = 'CSV_DIR'
        AND ROWNUM = 1;

    l_cur_ach                           cur_ach%rowtype;
    l_cur_dir                           cur_dir%rowtype;
    p_person_id                         NUMBER;
    p_payroll_id                        NUMBER;
    p_consolidation_set_id              NUMBER;
    p_assignment_set_id                 NUMBER;
    p_effective_date                    DATE;
    p_action_type                       VARCHAR2(20);
    lv_first_name                       VARCHAR2(150);
    lv_last_name                        VARCHAR2(150);
    lv_emp_no                           VARCHAR2(30);
    lv_rt                               VARCHAR2(20);
    lv_ac_number                        VARCHAR2(20);
    lv_amount                           VARCHAR2(20);
    lv_dirname                          VARCHAR2(2000);
    lv_filename                         VARCHAR2(200);
    out_file                            utl_file.file_type;
BEGIN
    p_payroll_id := '&1';
    p_consolidation_set_id := '&2';
    p_effective_date := '&3';
    p_assignment_set_id := '&4';
    p_person_id := '&5';
    p_action_type := '&6';
    lv_filename := 'ach_' || to_char(TO_DATE(p_effective_date), 'RRRRMMDD') 
        || '_' || to_char(sysdate, 'RRRRMMDD.HH24.MI.SS') || '.csv';

    out_file := utl_file.fopen('CSV_DIR', lv_filename, 'W');
    utl_file.put_line(out_file, 'Last Name,First Name,Employee ID,RT,A/C Number,Amount');
    OPEN cur_ach(p_payroll_id, p_consolidation_set_id, p_effective_date, 
        p_assignment_set_id, p_person_id, p_action_type);
    LOOP
        FETCH cur_ach INTO l_cur_ach;
        EXIT WHEN cur_ach%notfound;
        lv_first_name := NULL;
        lv_last_name := NULL;
        lv_emp_no := NULL;
        lv_ac_number := NULL;
        lv_amount := NULL;
        lv_rt := NULL;
        lv_first_name := l_cur_ach.first_name;
        lv_last_name := l_cur_ach.last_name;
        lv_emp_no := l_cur_ach.emp_no;
        lv_ac_number := l_cur_ach.account_number;
        lv_amount := trim(to_char(TO_NUMBER(l_cur_ach.amount), '99999999990.00'));
        lv_rt := l_cur_ach.rt;
        dbms_output.put_line(lv_last_name || ',' || lv_first_name || ','
            || lv_emp_no || ',' || lv_rt || ',' || lv_ac_number || ',' || lv_amount);
        utl_file.put_line(out_file, lv_last_name || ',' || lv_first_name || ',' || lv_emp_no
            || ',' || lv_rt || ',' || lv_ac_number || ',' || lv_amount);
    END LOOP;
    CLOSE cur_ach;
    utl_file.fclose(out_file);

    OPEN cur_dir;
    FETCH cur_dir INTO l_cur_dir;
    lv_dirname := l_cur_dir.directory_path;
    CLOSE cur_dir;
  
  --dbms_output.put_line('Output file created: ' || lv_dirname || '/' || lv_filename);
END;
/