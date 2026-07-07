--------------------------------------------------------------------------------
-- document_alerts_setup.sql
--------------------------------------------------------------------------------
-- Document all custom alerts in an EBS instance.
--------------------------------------------------------------------------------
-- 07-JUN-2017  vseeram  Created
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. Write code to 'document' the alerts in a table 
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON SIZE UNLIMITED;
DECLARE
    x                     VARCHAR2(1);

    -- get database name
    CURSOR db_cur IS
    SELECT
        db.name
    FROM
        v$database db;


    -- get list of all alerts
    CURSOR alrt_cur IS
    SELECT
        fat.application_name,
        fat2.application_name "TABLE_APPLICATION_NAME",
        aa.*,
        CASE aa.enabled_flag
            WHEN 'Y' THEN
                '<checked>'
            WHEN 'N' THEN
                '<unchecked>'
            ELSE
                ' '
        END "ENABLED",
        CASE aa.alert_condition_type
            WHEN 'P' THEN
                'Periodic'
            WHEN 'E' THEN
                'Event'
            ELSE
                ' '
        END "CONDITION",
        CASE aa.frequency_type
            WHEN 'C' THEN
                'Every N Calendar Days'
            WHEN 'O' THEN
                'On Demand'
            WHEN 'M' THEN
                'On Day of the Month'
            ELSE
                ' '
        END "FREQUENCY"
    FROM
        alr_alerts         aa,
        fnd_application_tl fat,
        fnd_application_tl fat2
    WHERE
        1 = 1
        AND aa.application_id = fat.application_id
        AND aa.table_application_id = fat2.application_id (+)
        AND aa.alert_name LIKE 'XX%'
        AND aa.application_id = 800
        AND aa.enabled_flag = 'Y'
    ORDER BY
        aa.alert_name ASC;


    -- get all alert actions for alert ID p_alert_id
    CURSOR alrt_actions_cur (
        p_alert_id IN NUMBER
    ) IS
    SELECT
        aa.*,
        nvl(aa.description, '<blank>')    "DESCRIPTION2",
        CASE aa.enabled_flag
            WHEN 'Y' THEN
                '<checked>'
            ELSE
                '<unchecked>'
        END                               "ENABLED",
        CASE aa.action_level_type
            WHEN 'S' THEN
                'Summary'
            WHEN 'D' THEN
                'Detail'
            ELSE
                'No Exception'
        END                               "ACTION_LEVEL",
        nvl(aa.cc_recipients, '<blank>')  "CC",
        nvl(aa.bcc_recipients, '<blank>') "BCC",
        CASE aa.column_wrap_flag
            WHEN 'Y' THEN
                'Wrap'
            ELSE
                aa.column_wrap_flag
        END                               "COLUMN_WRAP"
    FROM
        alr_actions aa
    WHERE
            1 = 1
        AND alert_id = p_alert_id
        AND enabled_flag = 'Y';


    -- get all alert action sets for alert ID p_alert_id
    CURSOR alrt_action_sets_cur (
        p_alert_id IN NUMBER
    ) IS
    SELECT
        aas.*,
        CASE aas.enabled_flag
            WHEN 'Y' THEN
                '<checked>'
            ELSE
                '<unchecked>'
        END "ENABLED",
        CASE aas.suppress_flag
            WHEN 'Y' THEN
                '<checked>'
            ELSE
                '<unchecked>'
        END "SUPPRESS"
    FROM
        alr_action_sets aas
    WHERE
        alert_id = p_alert_id;


    -- get all alert action set details for alert ID p_alert_id
    CURSOR alrt_action_set_det_cur (
        p_alert_id IN NUMBER
    ) IS
    SELECT
        aasm.sequence,
        aa.name,
        CASE aa.action_type
            WHEN 'M' THEN
                'Action: Message'
            WHEN 'C' THEN
                'Concurrent Program'
            WHEN 'S' THEN
                'SQL Statement Script'
            WHEN 'O' THEN
                'Operating System Script'
            ELSE
                aasm.abort_flag
        END                "ACTIONTYPE",
        CASE aasm.abort_flag
            WHEN 'A' THEN
                'Abort'
            ELSE
                aasm.abort_flag
        END                "ACTION",
        CASE aasm.enabled_flag
            WHEN 'Y' THEN
                '<checked>'
            ELSE
                '<unchecked>'
        END                "ENABLED",  
        aa.end_date_active "END_DATE"
    FROM
        alr_action_set_members aasm,
        alr_actions            aa
    WHERE
            1 = 1
        AND aasm.action_id = aa.action_id
        AND aa.enabled_flag = 'Y'
        AND aa.alert_id = p_alert_id;


    -- get all alert details for alert ID p_alert_id
    CURSOR alrt_alert_details_cur (
        p_alert_id IN NUMBER
    ) IS
    SELECT
        aai.alert_id,
        fou.oracle_username,
        haou.name "ORG_NAME",
        CASE aai.enabled_flag
            WHEN 'Y' THEN
                '<checked>'
            ELSE
                '<unchecked>'
        END       "ENABLED"
    FROM
        alr_alert_installations   aai,
        fnd_oracle_userid         fou,
        hr_all_organization_units haou
    WHERE
            1 = 1
        AND aai.oracle_id = fou.oracle_id
        AND aai.data_group_id = haou.organization_id (+)
        AND aai.alert_id = p_alert_id;

    l_dbname                            db_cur%rowtype;
    l_alrt                              alrt_cur%rowtype;
    l_alrt_actions                      alrt_actions_cur%rowtype;
    l_alrt_action_sets                  alrt_action_sets_cur%rowtype;
    l_alrt_action_set_det               alrt_action_set_det_cur%rowtype;
    l_alrt_alert_details                alrt_alert_details_cur%rowtype;
    l_counter                           NUMBER;
    l_separator                         VARCHAR2(3);
    l_day                               NUMBER;
    lv_dbname                           VARCHAR2(255);
    lv_header                           VARCHAR2(255);
BEGIN
    dbms_output.enable(buffer_size => NULL);
    l_counter := 1;
    l_separator := ' : '; -- CHR(9);

    -- get instance name
    OPEN db_cur;
    LOOP
        FETCH db_cur INTO l_dbname;
        EXIT WHEN db_cur%notfound;
        lv_dbname := l_dbname.name;
        dbms_output.put_line('');
        dbms_output.put_line('Processing instance: ' || l_dbname.name);
        dbms_output.put_line('');
    END LOOP;

    CLOSE db_cur; 

    -- loop through all alerts
    OPEN alrt_cur;
    LOOP
        FETCH alrt_cur INTO l_alrt;
        EXIT WHEN alrt_cur%notfound;
        lv_header := l_alrt.alert_name
                     || ' ('
                     || l_dbname.name
                     || ')';
--    l_alrt.alert_name := l_alrt.alert_name || ' (' || l_dbname.name || ')';
        dbms_output.put_line(l_counter || '. ' || lv_header);
        dbms_output.put_line('');
        dbms_output.put_line('A. Define Alert: ' || lv_header);
        dbms_output.put_line('');
        dbms_output.put_line('Application                   ' || l_separator
                             || l_alrt.application_name);
        dbms_output.put_line('Name                          ' || l_separator
                             || l_alrt.alert_name);
        dbms_output.put_line('Description                   ' || l_separator
                             || l_alrt.description);
        dbms_output.put_line('Enabled                       ' || l_separator
                             || l_alrt.enabled);
        dbms_output.put_line('Alert Condition Type          ' || l_separator
                             || l_alrt.condition);
        IF l_alrt.alert_condition_type = 'P' THEN
            dbms_output.put_line('Frequency                     ' || l_separator
                                 || l_alrt.frequency);
            dbms_output.put_line('Day                           ' || l_separator
                                 || l_alrt.monthly_check_day_num
                                 || l_alrt.days_between_checks);

            dbms_output.put_line('Start Time                    ' || l_separator
                                 || to_char(TO_DATE(l_alrt.check_start_time / 3600, 'HH24:MI:SS'), 'HH24:MI:SS'));

            dbms_output.put_line('End Time                      ' || l_separator
                                 || l_alrt.check_end_time);
        ELSIF l_alrt.alert_condition_type = 'E' THEN
            dbms_output.put_line('Application                   ' || l_separator
                                 || l_alrt.table_application_name);
            dbms_output.put_line('Table                         ' || l_separator
                                 || l_alrt.table_name);
            dbms_output.put_line('After Insert                  ' || l_separator
                                 || l_alrt.insert_flag);
            dbms_output.put_line('After Update                  ' || l_separator
                                 || l_alrt.update_flag);
        END IF;

        dbms_output.put_line('Keep                          ' || l_separator
                             || l_alrt.maintain_history_days);
        dbms_output.put_line('End Date                      ' || l_separator
                             || l_alrt.end_date_active);
        dbms_output.put_line('');
        dbms_output.put_line('SQL Statement');
        dbms_output.put_line(l_alrt.sql_statement_text);
        dbms_output.put_line('');

        -- B. Extract actions and C. action details
        OPEN alrt_actions_cur(l_alrt.alert_id);
        LOOP
            FETCH alrt_actions_cur INTO l_alrt_actions;
            EXIT WHEN alrt_actions_cur%notfound;
            dbms_output.put_line('');
            dbms_output.put_line('B. Define Actions: ' || lv_header);
            dbms_output.put_line('');
            dbms_output.put_line('Action Name                   ' || l_separator
                                 || l_alrt_actions.name);
            dbms_output.put_line('Action Description            ' || l_separator
                                 || l_alrt_actions.description2);
            dbms_output.put_line('Action Level                  ' || l_separator
                                 || l_alrt_actions.action_level);
            dbms_output.put_line('');
            dbms_output.put_line('C. Define Action Details: ' || lv_header);
            dbms_output.put_line('');
            dbms_output.put_line('Action Type                   ' || l_separator
                                 || CASE l_alrt_actions.action_type
                WHEN 'M' THEN
                    'Message'
                ELSE l_alrt_actions.action_type
            END);

            dbms_output.put_line('To                            ' || l_separator
                                 || l_alrt_actions.to_recipients);
            dbms_output.put_line('Subject                       ' || l_separator
                                 || l_alrt_actions.subject);
            dbms_output.put_line('Cc                            ' || l_separator
                                 || l_alrt_actions.cc);
            dbms_output.put_line('Bcc                           ' || l_separator
                                 || l_alrt_actions.bcc);
            dbms_output.put_line('Column Overflow               ' || l_separator
                                 || l_alrt_actions.column_wrap);
            dbms_output.put_line('Max Width                     ' || l_separator
                                 || l_alrt_actions.maximum_summary_message_width);
            dbms_output.put_line('');
            dbms_output.put_line('Text                          ' || l_separator);
            dbms_output.put_line(l_alrt_actions.body);
        END LOOP;

        CLOSE alrt_actions_cur;

        -- D. Extract action sets
        OPEN alrt_action_sets_cur(l_alrt.alert_id);
        LOOP
            FETCH alrt_action_sets_cur INTO l_alrt_action_sets;
            EXIT WHEN alrt_action_sets_cur%notfound;
            dbms_output.put_line('');
            dbms_output.put_line('D. Define Action Sets: ' || lv_header);
            dbms_output.put_line('');
            dbms_output.put_line('Action Set Seq                ' || l_separator
                                 || l_alrt_action_sets.sequence);
            dbms_output.put_line('Action Set Name               ' || l_separator
                                 || l_alrt_action_sets.name);
            dbms_output.put_line('Action Set Description        ' || l_separator
                                 || l_alrt_action_sets.description);
            dbms_output.put_line('Action Set Suppress Duplicates' || l_separator
                                 || l_alrt_action_sets.suppress);
            dbms_output.put_line('Action Set Enabled            ' || l_separator
                                 || l_alrt_action_sets.enabled);
            dbms_output.put_line('Action Set End Date           ' || l_separator
                                 || l_alrt_action_sets.end_date_active);
            dbms_output.put_line(' ');
        END LOOP;

        CLOSE alrt_action_sets_cur; 

        -- E. Extract action set details
        OPEN alrt_action_set_det_cur(l_alrt.alert_id);
        LOOP
            FETCH alrt_action_set_det_cur INTO l_alrt_action_set_det;
            EXIT WHEN alrt_action_set_det_cur%notfound;
            dbms_output.put_line('');
            dbms_output.put_line('E. Define Action Set Details: ' || lv_header);
            dbms_output.put_line('');
            dbms_output.put_line('Action Set Details Seq        ' || l_separator
                                 || l_alrt_action_set_det.sequence);
            dbms_output.put_line('Action Set Details Action     ' || l_separator
                                 || l_alrt_action_set_det.name);
            dbms_output.put_line('Action Set Details Type       ' || l_separator
                                 || l_alrt_action_set_det.actiontype);
            dbms_output.put_line('Action Set Details Action     ' || l_separator
                                 || l_alrt_action_set_det.action);
            dbms_output.put_line('Action Set Details Enabled    ' || l_separator
                                 || l_alrt_action_set_det.enabled);
            dbms_output.put_line('Action Set Details End Date   ' || l_separator
                                 || l_alrt_action_set_det.end_date);
            dbms_output.put_line(' ');
        END LOOP;

        CLOSE alrt_action_set_det_cur; 

        -- F. Extract alert details
        OPEN alrt_alert_details_cur(l_alrt.alert_id);
        LOOP
            FETCH alrt_alert_details_cur INTO l_alrt_alert_details;
            EXIT WHEN alrt_alert_details_cur%notfound;
            dbms_output.put_line('');
            dbms_output.put_line('F. Define Alert Details: ' || lv_header);
            dbms_output.put_line('');
            dbms_output.put_line('Alert Details Oracle ID       ' || l_separator
                                 || l_alrt_alert_details.oracle_username);
            dbms_output.put_line('Alert Details Operating Unit  ' || l_separator
                                 || l_alrt_alert_details.org_name);
            dbms_output.put_line('Alert Details Enabled         ' || l_separator
                                 || l_alrt_alert_details.enabled);
            dbms_output.put_line(' ');
        END LOOP;

        CLOSE alrt_alert_details_cur;
        l_counter := l_counter + 1;
        dbms_output.put_line('--------------------------------------------------------------------------------');
        dbms_output.put_line(' ');
    END LOOP;

    CLOSE alrt_cur;
END;
/