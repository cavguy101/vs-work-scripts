--------------------------------------------------------------------------------
-- document_conc_setup.sql
--------------------------------------------------------------------------------
-- Document all custom XX concurrent programs in an EBS instance.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. Find list of concurrent program
--------------------------------------------------------------------------------
SELECT
    *
FROM
    dba_objects
WHERE
        1 = 1
    AND object_name LIKE 'FND_CONCURRENT%'
    AND object_type IN ( 'TABLE' )
ORDER BY
    1,
    2;

--------------------------------------------------------------------------------
-- 2. Find all concurrent programs set up only during the HR project.
-- Run this code against CRP1 and EBSPROD, and compare the concurrent program
-- definition names.
--------------------------------------------------------------------------------
SELECT
    db.name,
    fcpt.user_concurrent_program_name program,
    fcp.enabled_flag                  enabled,
    fcp.concurrent_program_name       short_name,
    fat.application_name              application,
    fcpt.description,
    fe.executable_name,
    fl.meaning                        executable_method,
    fcp.execution_options             options,
    fcp.request_priority              priority,
    fcp.output_file_type              output_format,
    fcp.save_output_flag              save,
    fcp.print_flag                    print,
    fcp.minimum_width                 columns,
    fcp.minimum_length                "ROWS",
    fcp.output_print_style            style,
    fcp.required_style                style_required,
    fcp.printer_name                  printer,
    fcp.srs_flag,
    fcp.run_alone_flag,
    fcp.enable_trace,
    fcp.recalc_parameters,
    fcp.restart,
    fcp.nls_compliant,
    fcp.executable_id
FROM
    v$database                 db,
    fnd_concurrent_programs    fcp,
    fnd_concurrent_programs_tl fcpt,
    fnd_executables            fe,
    fnd_executables_tl         fet,
    fnd_lookups                fl,
    fnd_application_tl         fat
WHERE
        1 = 1
    AND fcp.application_id = fat.application_id
    AND fcp.concurrent_program_id = fcpt.concurrent_program_id
    AND fcp.executable_id = fe.executable_id
    AND fe.executable_id = fet.executable_id
    AND fe.execution_method_code = fl.lookup_code
    AND fl.lookup_type = 'CP_EXECUTION_METHOD_CODE'
    AND fcp.concurrent_program_name LIKE '%XX%'
    AND fcp.creation_date >= '01-JUN-2015'
ORDER BY
    2,
    5;

SELECT
    *
FROM
    fnd_concurrent_programs;

--------------------------------------------------------------------------------
-- 3. Find concurrent program executables set up only during HR project
-- Run this code against CRP1 and EBSPROD, and compare the executable names.
--------------------------------------------------------------------------------
SELECT
    db.name,
    fet.user_executable_name "EXECUTABLE",
    fe.executable_name       "SHORT_NAME",
    fat.application_name     "APPLICATION",
    fet.description          "DESCRIPTION",
    fl.meaning               execution_method,
    fe.execution_file_name
FROM
    v$database         db,
    fnd_executables    fe,
    fnd_executables_tl fet,
    fnd_application_tl fat,
    fnd_lookups        fl
WHERE
        1 = 1
    AND fe.executable_id = fet.executable_id
    AND fe.application_id = fat.application_id
    AND fe.execution_method_code = fl.lookup_code
    AND fl.lookup_type = 'CP_EXECUTION_METHOD_CODE'
    AND fe.executable_name LIKE 'XX%'
    AND fe.creation_date >= '01-JUN-2015'
ORDER BY
    application_name,
    fe.executable_name;

SELECT
    *
FROM
    fnd_executables;

SELECT
    *
FROM
    fnd_lookups
WHERE
    lookup_type = 'CP_EXECUTION_METHOD_CODE'; -- meaning = 'Oracle Reports';

--------------------------------------------------------------------------------
-- 4. Find concurrent program parameters set up during HR project
--------------------------------------------------------------------------------
SELECT
    db.name,
    fcpl.user_concurrent_program_name    program,
    fav.application_name                 application,
    fdfcuv.column_seq_num                seq,
    fdfcuv.end_user_column_name          parameter,
    fdfcuv.form_left_prompt              description,
    fdfcuv.enabled_flag                  enabled,
    ffvs.flex_value_set_name             value_set,
    ffvs.description                     vs_description,
    flv.meaning                          default_type,
    fdfcuv.default_value,
    fdfcuv.required_flag                 required,
    fdfcuv.security_enabled_flag         enable_security,
    fdfcuv.display_flag                  display,
    fdfcuv.display_size,
    fdfcuv.maximum_description_len       description_size,
    fdfcuv.concatenation_description_len concatenated_description_size,
    fdfcuv.form_left_prompt              prompt,
    fdfcuv.srw_param                     token
FROM
    v$database                  db,
    fnd_concurrent_programs     fcp,
    fnd_concurrent_programs_tl  fcpl,
    fnd_descr_flex_col_usage_vl fdfcuv,
    fnd_flex_value_sets         ffvs,
    fnd_lookup_values           flv,
    fnd_application_vl          fav
WHERE
        fcp.concurrent_program_id = fcpl.concurrent_program_id
    AND fcpl.user_concurrent_program_name LIKE 'XX%'
    AND fav.application_id <> 20003
    AND fcpl.language = 'US'
    AND fav.application_id = fcp.application_id
    AND fdfcuv.descriptive_flexfield_name = '$SRS$.' || fcp.concurrent_program_name
    AND ffvs.flex_value_set_id = fdfcuv.flex_value_set_id
    AND flv.lookup_type (+) = 'FLEX_DEFAULT_TYPE'
    AND flv.lookup_code (+) = fdfcuv.default_type
    AND flv.language (+) = userenv('LANG')
ORDER BY
    2,
    fdfcuv.column_seq_num;

SELECT
    *
FROM
    fnd_descr_flex_col_usage_vl;

SELECT
    *
FROM
    fnd_flex_value16 characters_sets;

SELECT
    *
FROM
    fnd_lookup_values
WHERE
    meaning = 'Profile';

--------------------------------------------------------------------------------
-- 5. Match parameter setup in table with screen
--------------------------------------------------------------------------------
SELECT
    db.name,
    fcpl.user_concurrent_program_name    "PROGRAM",
    fav.application_name                 "APPLICATION",
--  fdfcuv.*,
    fdfcuv.column_seq_num                "SEQ",
    fdfcuv.end_user_column_name          "PARAMETER",
    fdfcuv.enabled_flag                  "ENABLED",
    ffvs.flex_value_set_name             "VALUE SET",
--  ffvs.description,
    fdfcuv.default_type                  "DEFAULT_TYPE",
    fdfcuv.default_value                 "DEFAULT_VALUE",
    fdfcuv.required_flag                 "REQUIRED",
    fdfcuv.security_enabled_flag         "ENABLE_SECURITY",
    fdfcuv.display_flag                  "DISPLAY",
    fdfcuv.display_size                  "DISPLAY_SIZE",
    fdfcuv.maximum_description_len       "DESCRIPTION_SIZE",
    fdfcuv.concatenation_description_len "CONCATENATED DESCRIPTION SIZE",
    fdfcuv.form_left_prompt              "PROMPT",
    fdfcuv.srw_param                     "TOKEN"
--  (CASE WHEN fdfcuv.end_user_column_name = fdfcuv.form_left_prompt THEN 'TRUE' ELSE 'FALSE' END) BOOL,
--  (fdfcuv.end_user_column_name = fdfcuv.form_left_prompt) bool,
--  fdfcuv.flex_value_set_id,
--  flv.meaning default_type
FROM
    v$database                  db,
    fnd_concurrent_programs     fcp,
    fnd_concurrent_programs_tl  fcpl,
    fnd_descr_flex_col_usage_vl fdfcuv,
    fnd_flex_value_sets         ffvs,
    fnd_lookup_values           flv,
    fnd_application_vl          fav
WHERE
        fcp.concurrent_program_id = fcpl.concurrent_program_id
    AND fcpl.user_concurrent_program_name LIKE 'XX%' -- = :conc_prg_name
    AND fav.application_id <> 20003
    AND fcpl.language = 'US'
    AND fav.application_id = fcp.application_id
    AND fdfcuv.descriptive_flexfield_name = '$SRS$.' || fcp.concurrent_program_name
    AND ffvs.flex_value_set_id = fdfcuv.flex_value_set_id
    AND flv.lookup_type (+) = 'flex_default_type'
    AND flv.lookup_code (+) = fdfcuv.default_type
    AND flv.language (+) = userenv('LANG')
ORDER BY
    2,
    fdfcuv.column_seq_num;

--------------------------------------------------------------------------------
-- 2. Write code to 'document' the concurrent programs
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    x            VARCHAR2(1);
  
    -- concurrent program
    CURSOR conc_cur IS
    SELECT
        db.name,
        fcp.concurrent_program_id,
        fcpt.user_concurrent_program_name program,
        fcp.enabled_flag                  enabled,
        fcp.concurrent_program_name       short_name,
        fat.application_name              application,
        fcpt.description,
        fe.executable_name,
        fl.meaning                        executable_method,
        fcp.execution_options             options,
        fcp.request_priority              priority,
        fcp.output_file_type              output_format,
        fcp.save_output_flag              save,
        fcp.print_flag                    print,
        fcp.minimum_width                 numcols,
        fcp.minimum_length                numrows,
        fcp.output_print_style            style,
        fcp.required_style                style_required,
        fcp.printer_name                  printer,
        fcp.srs_flag,
        fcp.run_alone_flag,
        fcp.enable_trace,
        fcp.recalc_parameters,
        fcp.restart,
        fcp.nls_compliant,
        fcp.executable_id
    FROM
        v$database                 db,
        fnd_concurrent_programs    fcp,
        fnd_concurrent_programs_tl fcpt,
        fnd_executables            fe,
        fnd_executables_tl         fet,
        fnd_lookups                fl,
        fnd_application_tl         fat
    WHERE
            1 = 1
        AND fcp.application_id = fat.application_id
        AND fcp.concurrent_program_id = fcpt.concurrent_program_id
        AND fcp.executable_id = fe.executable_id
        AND fe.executable_id = fet.executable_id
        AND fe.execution_method_code = fl.lookup_code
        AND fl.lookup_type = 'CP_EXECUTION_METHOD_CODE'
        AND fcp.concurrent_program_name LIKE '%XX%'
        AND fcp.creation_date >= '01-JUN-2015'
    ORDER BY
        2,
        5;

    -- concurrent program executable
    CURSOR conc_exec_cur (
        p_executable_id IN NUMBER
    ) IS
    SELECT
        db.name,
        fet.user_executable_name "EXECUTABLE",
        fe.executable_name       "SHORT_NAME",
        fat.application_name     "APPLICATION",
        fet.description          "DESCRIPTION",
        fl.meaning               execution_method,
        fe.execution_file_name
    FROM
        v$database         db,
        fnd_executables    fe,
        fnd_executables_tl fet,
        fnd_application_tl fat,
        fnd_lookups        fl
    WHERE
            1 = 1
        AND fe.executable_id = fet.executable_id
        AND fe.application_id = fat.application_id
        AND fe.execution_method_code = fl.lookup_code
        AND fl.lookup_type = 'CP_EXECUTION_METHOD_CODE'
        AND fe.executable_name LIKE 'XX%'
        AND fe.creation_date >= '01-JUN-2015'
        AND fe.executable_id = p_executable_id
    ORDER BY
        application_name,
        fe.executable_name;

    -- concurrent program parameters
    CURSOR conc_param_cur (
        p_conc_prg_id IN NUMBER
    ) IS
    SELECT
        db.name,
        fcp.concurrent_program_id,
        fcpl.user_concurrent_program_name    program,
        fav.application_name                 application,
        fdfcuv.column_seq_num                seq,
        fdfcuv.end_user_column_name          parameter,
        fdfcuv.form_left_prompt              description,
        fdfcuv.enabled_flag                  enabled,
        ffvs.flex_value_set_name             value_set,
        ffvs.description                     vs_description,
        flv.meaning                          default_type,
        fdfcuv.default_value,
        fdfcuv.required_flag                 required,
        fdfcuv.security_enabled_flag         enable_security,
        fdfcuv.display_flag                  display,
        fdfcuv.display_size,
        fdfcuv.maximum_description_len       description_size,
        fdfcuv.concatenation_description_len concatenated_description_size,
        fdfcuv.form_left_prompt              prompt,
        fdfcuv.srw_param                     token
    FROM
        v$database                  db,
        fnd_concurrent_programs     fcp,
        fnd_concurrent_programs_tl  fcpl,
        fnd_descr_flex_col_usage_vl fdfcuv,
        fnd_flex_value_sets         ffvs,
        fnd_lookup_values           flv,
        fnd_application_vl          fav
    WHERE
            fcp.concurrent_program_id = fcpl.concurrent_program_id
        AND fcpl.user_concurrent_program_name LIKE 'XX%'
        AND fav.application_id <> 20003
        AND fcpl.language = 'US'
        AND fav.application_id = fcp.application_id
        AND fdfcuv.descriptive_flexfield_name = '$SRS$.' || fcp.concurrent_program_name
        AND ffvs.flex_value_set_id = fdfcuv.flex_value_set_id
        AND flv.lookup_type (+) = 'FLEX_DEFAULT_TYPE'
        AND flv.lookup_code (+) = fdfcuv.default_type
        AND flv.language (+) = userenv('LANG')
        AND fcp.concurrent_program_id = p_conc_prg_id
    ORDER BY
        2,
        fdfcuv.column_seq_num;

    l_conc       conc_cur%rowtype;
    l_conc_exec  conc_exec_cur%rowtype;
    l_conc_param conc_param_cur%rowtype;
    l_counter    NUMBER;

    PROCEDURE printout (
        p_label IN VARCHAR2,
        p_value IN VARCHAR2 DEFAULT '|'
    ) IS
        lv_value             VARCHAR2(1000);
        lv_separator         VARCHAR2(2);
        lv_for_documentation BOOLEAN;
    BEGIN
        lv_separator := ':';
        lv_for_documentation := TRUE;
        IF p_value = 'Y' THEN
            lv_value := '<checked>';
        ELSIF p_value = 'N' THEN
            lv_value := '<unchecked>';
        ELSIF p_value IS NULL THEN
            lv_value := '<blank>';
        ELSE
            lv_value := p_value;
        END IF;

        IF p_label IS NULL THEN
            dbms_output.put_line('');
        ELSIF lv_value <> '|' THEN
            BEGIN
                IF lv_for_documentation = false THEN
                    dbms_output.put_line(rpad(p_label, 30) || lv_separator || lv_value);
                ELSE
                    dbms_output.put_line(lv_value);
                END IF;

            END;
        ELSE
            dbms_output.put_line(p_label);
        END IF;

    END printout;

BEGIN
    dbms_output.enable(buffer_size => NULL);
    --  printout('Hello, world');
    l_counter := 1;
    -- extract alert details
    OPEN conc_cur;
    LOOP
        FETCH conc_cur INTO l_conc;
        EXIT WHEN conc_cur%notfound;
        printout(l_counter || '. ' || ' Define ' || l_conc.program || ' Concurrent Program');

        printout('');
        OPEN conc_exec_cur(l_conc.executable_id);
        LOOP
            FETCH conc_exec_cur INTO l_conc_exec;
            EXIT WHEN conc_exec_cur%notfound;
            printout('Define Concurrent Program Executable: ' || l_conc.program);
            printout('');
            printout('Executable', l_conc_exec.executable);
            printout('Short Name', l_conc_exec.short_name);
            printout('Application', l_conc_exec.application);
            printout('Description', l_conc_exec.description);
            printout('Execution Method', l_conc_exec.execution_method);
            printout('Execution File Name', l_conc_exec.execution_file_name);
            printout('');
        END LOOP;

        CLOSE conc_exec_cur;
        printout('Define Concurrent Program: ' || l_conc.program);
        printout('');
        printout('Program', l_conc.program);
        printout('Enabled', l_conc.enabled);
        printout('Short Name', l_conc.short_name);
        printout('Application', l_conc.application);
        printout('Description', l_conc.description);
        printout('Executable Name', l_conc.executable_name);
        printout('Executable Method', l_conc.executable_method);
        printout('Options', l_conc.options);
        printout('Priority', l_conc.priority);
        printout('Use in SRS', l_conc.srs_flag);
        printout('Run Alone', l_conc.run_alone_flag);
        printout('Enable Trace', l_conc.enable_trace);
        printout('Recalculate Default Params', l_conc.recalc_parameters);
        printout('Allow Disabled Values', 'N');
        printout('Restart on System Failure', l_conc.restart);
        printout('NLS Compliant', l_conc.nls_compliant);
        printout('Output Format', l_conc.output_format);
        printout('Save', l_conc.save);
        printout('Print', l_conc.print);
        printout('Columns', l_conc.numcols);
        printout('Rows', l_conc.numrows);
        printout('Style', l_conc.style);
        printout('Style Required', l_conc.style_required);
        printout('Printer', l_conc.printer);
        printout('');
        printout('Define Concurrent Program Parameters: ' || l_conc.program);
        printout('');
        OPEN conc_param_cur(l_conc.concurrent_program_id);
        LOOP
            FETCH conc_param_cur INTO l_conc_param;
            EXIT WHEN conc_param_cur%notfound;
            printout('Program', l_conc_param.program);
            printout('Application', l_conc_param.application);
            printout('Seq', l_conc_param.seq);
            printout('Parameter', l_conc_param.parameter);
            printout('Description', l_conc_param.description);
            printout('Enabled', l_conc_param.enabled);
            printout('Value Set', l_conc_param.value_set);
            printout('Description', l_conc_param.description);
            printout('Default Type', l_conc_param.default_type);
            printout('Default Value', l_conc_param.default_value);
            printout('Required', l_conc_param.required);
            printout('Enable Security', l_conc_param.enable_security);
            printout('Display', l_conc_param.display);
            printout('Display Size', l_conc_param.display_size);
            printout('Description Size', l_conc_param.description_size);
            printout('Concat Description Size', l_conc_param.concatenated_description_size);
            printout('Prompt', l_conc_param.prompt);
            printout('Token', l_conc_param.token);
            printout('');
        END LOOP;

        CLOSE conc_param_cur;
        l_counter := l_counter + 1;
    END LOOP;

    CLOSE conc_cur;
END;
/

/*
-- extract alert action details
OPEN alrt_actions_cur(l_alrt.alert_id);

LOOP
    FETCH alrt_actions_cur INTO l_alrt_actions;
    EXIT WHEN alrt_actions_cur%notfound;
    printout('Actions');
    printout('');
    printout('Action Name', l_alrt_actions.name);
    printout('Action Description', l_alrt_actions.description);
    printout('Action Level',
            CASE l_alrt_actions.action_level_type
                WHEN 'S' THEN
                    'Summary'
                WHEN 'D' THEN
                    'Detail'
                ELSE 'No Exception'
            END
    );

    printout('Action Type',
            CASE l_alrt_actions.action_type
                WHEN 'M' THEN
                    'Message'
                ELSE l_alrt_actions.action_type
            END
    );

    printout('To', l_alrt_actions.to_recipients);
    printout('Subject', l_alrt_actions.subject);
    printout('Cc', l_alrt_actions.cc_recipients);
    printout('Bcc', l_alrt_actions.bcc_recipients);
    printout('Column Overflow',
            CASE l_alrt_actions.column_wrap_flag
                WHEN 'Y' THEN
                    'Wrap'
                ELSE l_alrt_actions.column_wrap_flag
            END
    );

    printout('Max Width', l_alrt_actions.maximum_summary_message_width);
    printout('');
    printout('Body', l_alrt_actions.body);
END LOOP;

CLOSE alrt_actions_cur;
    -- extract alert action set details
OPEN alrt_action_sets_cur(l_alrt.alert_id);

LOOP
    FETCH alrt_action_sets_cur INTO l_alrt_action_sets;
    EXIT WHEN alrt_action_sets_cur%notfound;
    printout('Action Sets');
    printout('');
    printout('Action Set Seq', l_alrt_action_sets.sequence);
    printout('Action Set Name', l_alrt_action_sets.name);
    printout('Action Set Description', l_alrt_action_sets.description);
    printout('Action Set Suppress Duplicates',
            CASE l_alrt_action_sets.suppress_flag
                WHEN 'Y' THEN
                    '<checked>'
                ELSE '<unchecked>'
            END
    );
    printout('Action Set Enabled',
            CASE l_alrt_action_sets.enabled_flag
                WHEN 'Y' THEN
                    '<checked>'
                ELSE '<unchecked>'
            END
    );
    printout('Action Set End Date', l_alrt_action_sets.end_date_active);
    printout(' ');
END LOOP;

CLOSE alrt_action_sets_cur;

printout('');

l_counter := l_counter + 1;
  END LOOP;
  CLOSE alrt_cur;
END;
/
*/