--------------------------------------------------------------------------------
-- request_group_copy.sql
-- This script copies all concurrent programs from one request group (RG) to another. 
-- It does not copy the request units of type Application or Request Set.
--
-- This script consists of a two anonymous procedures:
-- 1. Copy concurrent programs from one request group to another
-- 2. Create a new request group
-- Do not run using F5 (Run Script) in SQL Developer; run only the procedure
-- needed using the Run Statement command.
--
-- Reference: https://erpschools.com/erps/api/sysadmin-api/api-concurrent-program-request-group
--
-- 24-FEB-2024  vseeram  Created
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
--------------------------------------------------------------------------------
-- 1. Add concurrent programs from source RG to destination RG
--------------------------------------------------------------------------------
DECLARE
    gv_src_request_group                CONSTANT VARCHAR2(2000) := 'Global SHRMS Reports & Process';
    gv_dest_request_group               CONSTANT VARCHAR2(2000) := 'VS Global SHRMS Reports';
    gv_dest_application                 VARCHAR2(2000);
    gn_counter                          NUMBER := 0;
    
    CURSOR rg_reports IS
    SELECT
        fcp.concurrent_program_name program_short_name,
        fat1.application_name
        -- frg.request_group_name
    FROM
        fnd_request_groups frg,
        fnd_request_group_units frgu,
        fnd_concurrent_programs fcp,
        fnd_concurrent_programs_tl fcpt,
        fnd_application_tl fat1
    WHERE
        1 = 1
        AND frg.request_group_id = frgu.request_group_id 
        AND frg.application_id = frgu.application_id 
        AND frgu.request_unit_id = fcp.concurrent_program_id
        AND frgu.unit_application_id = fcp.application_id
        AND fcp.concurrent_program_id = fcpt.concurrent_program_id
        AND fcp.application_id = fcpt.application_id
        AND frgu.unit_application_id = fat1.application_id
        AND frg.request_group_name = gv_src_request_group
    MINUS
    SELECT
        fcp.concurrent_program_name program_short_name,
        fat1.application_name
    FROM
        fnd_request_groups frg,
        fnd_request_group_units frgu,
        fnd_concurrent_programs fcp,
        fnd_concurrent_programs_tl fcpt,
        fnd_application_tl fat1
    WHERE
        1 = 1
        AND frg.request_group_id = frgu.request_group_id 
        AND frg.application_id = frgu.application_id 
        AND frgu.request_unit_id = fcp.concurrent_program_id
        AND frgu.unit_application_id = fcp.application_id
        AND fcp.concurrent_program_id = fcpt.concurrent_program_id
        AND fcp.application_id = fcpt.application_id
        AND frgu.unit_application_id = fat1.application_id
        AND frg.request_group_name = gv_dest_request_group
    ;

BEGIN
    SELECT
        fat.application_name
    INTO 
        gv_dest_application
    FROM
        fnd_application_tl fat,
        fnd_request_groups frg
    WHERE 
        1 = 1
        AND fat.application_id = frg.application_id 
        AND frg.request_group_name = gv_dest_request_group;

    FOR x IN rg_reports LOOP
        dbms_output.put_line('Adding: ' || x.program_short_name || ', ' || x.application_name || ', ' || gv_dest_request_group || ', ' || gv_dest_application);
        
        fnd_program.add_to_group(x.program_short_name   -- program_short_name
        , x.application_name                            -- application
        , gv_dest_request_group                         -- report group name
        , gv_dest_application                           -- report group application
        );           
        gn_counter := gn_counter + 1;
    END LOOP;
    dbms_output.put_line(Chr(13) || Chr(10) || To_Char(gn_counter) || ' concurrent program(s) added to request group ' || gv_dest_request_group || '.');
    IF Nvl(:p_commit, ' ') = 'Y' THEN
        dbms_output.put_line('Committing...');
        COMMIT;
    ELSE
        dbms_output.put_line('Rolling back...');
        ROLLBACK;
    END IF;
END;
/



--------------------------------------------------------------------------------
-- 2. Add a new request group
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON
DECLARE
    c_new_request_group                 CONSTANT VARCHAR2(30) := 'VS Global SHRMS Reports';
    c_application                       CONSTANT VARCHAR2(2000) := 'Human Resources';
    c_short_code                        CONSTANT VARCHAR2(30) := 'VS_GLOBAL_HRMS_REP_PRO';
    c_description                       CONSTANT VARCHAR2(2000) := 'VS Global SHRMS Reports and Processes';

    gn_count                            NUMBER := 0;
BEGIN
    -- validate uniqueness of new request group name
    SELECT Count(*) INTO gn_count FROM fnd_request_groups WHERE request_group_name = c_new_request_group;
    IF gn_count > 0 THEN
        dbms_output.put_line('Request group ' || c_new_request_group || ' already exists, exiting...');
        RETURN;
    END IF;

    -- validate existence of application
    SELECT Count(*) INTO gn_count FROM fnd_application_tl WHERE application_name = c_application;
    IF gn_count = 0 THEN
        dbms_output.put_line('Application ' || c_application || ' does not exist, exiting...');
        RETURN;
    END IF;

    -- validate uniqueness of new request group code
    SELECT Count(*) INTO gn_count FROM fnd_request_groups WHERE request_group_code = c_short_code;
    IF gn_count > 0 THEN
        dbms_output.put_line(c_short_code || ' already exists, exiting...');
        RETURN;
    END IF;


    dbms_output.put_line('Registering request group ' || c_new_request_group || '...');
    fnd_program.request_group(request_group => c_new_request_group,
        application => c_application,
        code => c_short_code,
        description => c_description
    );
    IF Nvl(:p_commit, ' ') = 'Y' THEN
        dbms_output.put_line('Committing...');
        COMMIT;
    ELSE
        dbms_output.put_line('Rolling back...');
        ROLLBACK;
    END IF;
    
    dbms_output.put_line('Exiting...');
END;
/
