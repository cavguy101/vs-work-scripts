-------------------------------------------------------------------------------
-- disable_customers.sql
-------------------------------------------------------------------------------
-- Given a list of customer numbers, make those customers inactive.
-- The program reads a list of customers from customers.csv, which is stored
-- on the database server, in the utl_file_dir directory, and makes API calls
-- to make those customers inactive.
-------------------------------------------------------------------------------
-- API to Update Customer Account in TCA R12
-- https://doyensys.com/blogs/api-to-update-customer-account-in-tca-r12/
-------------------------------------------------------------------------------
-- 31-JAN-2024  vseeram  Created
-------------------------------------------------------------------------------






SET SERVEROUTPUT ON
DECLARE
    -- initialize constants
    c_username                          CONSTANT VARCHAR2(30) := 'SYSADMIN';
    c_responsibility_name               CONSTANT VARCHAR2(50) := 'Receivables Manager';
    
    c_comma                             CONSTANT VARCHAR2(1)  := ','; -- separator for comma-separated values (CSV) datafiles
    v_context                           VARCHAR2(100);

    c_line_separator                    CONSTANT VARCHAR2(99) := RPad('+', 81, '-') || '+ ';
    c_yes                               CONSTANT VARCHAR2(1)  := 'Y';  -- 'Y'
    c_no                                CONSTANT VARCHAR2(1)  := 'N';  -- 'Y'
    c_debug_flag                        CONSTANT VARCHAR2(1)  := 'Y'; -- set to c_yes to turn on debugging
  
    -- initialize global variables/concurrent program parameters
    gv_commit                           VARCHAR2(1)   := Upper(NVL(('&commit'), c_no));
    gv_datafile                         VARCHAR2(255) := 'customers.csv'; -- NVL('&file_name', 'customers.csv');
    gv_directory                        VARCHAR2(255) := 'APPS_DATA_FILE_DIR'; -- NVL('&directory', 'APPS_DATA_FILE_DIR'); -- '/u01/oracle/TEST2/19.0.0/appsutil/outbound/TEST2_erpdbdev' on CBCL TEST2

    gv_input_line                       VARCHAR2(2000);
    gv_dest_dir                         VARCHAR2(2000);

    input_file                          utl_file.file_type;
    n_total_rows                        NUMBER := 0;
    n_total_successful                  NUMBER := 0;
    l_input_line                        VARCHAR2(2000);

    -- variables to store data read from input file
    v_customer_name                     VARCHAR2(255);
    v_customer_num                      VARCHAR2(255);

    -- for storing customer account record, and customer account site record
    v_cust_account_rec                  hz_cust_account_v2pub.cust_account_rec_type;
    v_cust_acct_site_rec                hz_cust_account_site_v2pub.cust_acct_site_rec_type;

    -- object version numbers for customer account and customer account site
    ln_ca_object_version_number         NUMBER;
    ln_cas_object_version_number        NUMBER;

    -- variables to store returned values from API call
    l_return_status                     VARCHAR2(10);
    l_msg_count                         NUMBER := 0;
    l_msg_data                          VARCHAR2(2000);
    
--    x_return_status                     VARCHAR2(2000);
--    x_msg_count                         NUMBER;
--    x_msg_data                          VARCHAR2(2000);

    -------------------------------------------------------------------------------
    -- function to set the application context before calling the API call
    -- ar_receipt_api_pub.create_and_apply
    -------------------------------------------------------------------------------
    FUNCTION p010_set_context (
        p_user_name                     IN VARCHAR2,
        p_resp_name                     IN VARCHAR2
    ) RETURN VARCHAR2 IS

        ln_user_id                      NUMBER;
        ln_resp_id                      NUMBER;
        ln_resp_appl_id                 NUMBER;
        lv_lang                         VARCHAR2(100);
        ln_org_id                       NUMBER;
        lv_session_lang                 VARCHAR2(100) := fnd_global.current_language;
        lv_return                       VARCHAR2(10) := 'T';
        lv_nls_lang                     VARCHAR2(100);

    BEGIN
        /* Get the user ID */
        SELECT DISTINCT
            user_id
        INTO
            ln_user_id
        FROM
            fnd_user
        WHERE
            user_name = p_user_name;

        /* Get the responsibility ID, application ID and language */
        SELECT
            responsibility_id,
            application_id,
            language
        INTO
            ln_resp_id,
            ln_resp_appl_id,
            lv_lang
        FROM
            fnd_responsibility_tl
        WHERE
            responsibility_name = p_resp_name;

        /* Get the org ID */
        SELECT
            organization_id
        INTO
            ln_org_id
        FROM
            hr_operating_units
        WHERE
            name = 'CBCL Operating Unit';

        mo_global.init('AR');

        /* Setting the oracle applications context for the particular session */
        fnd_global.apps_initialize(user_id => ln_user_id,resp_id => ln_resp_id,resp_appl_id => ln_resp_appl_id);

        /* Setting the org context for the particular session */
        mo_global.set_policy_context('S', ln_org_id);

        /* setting the nls context for the particular session */
        IF lv_session_lang != lv_lang THEN
            /* get the nls language information for setting the language context */
            SELECT
                nls_language
            INTO
                lv_nls_lang
            FROM
                fnd_languages
            WHERE
                language_code = lv_lang;
            fnd_global.set_nls_context(lv_nls_lang);
        END IF;

        RETURN lv_return;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p010_set_context');
            dbms_output.put_line(SQLERRM);
            RETURN 'F';
    END p010_set_context;

    -------------------------------------------------------------------------------
    -- initialize environment before running code
    -------------------------------------------------------------------------------
    PROCEDURE p020_initialize(p_username IN VARCHAR2, p_responsibility_name IN VARCHAR2, p_directory IN VARCHAR2, p_datafile IN VARCHAR2, p_input_file OUT utl_file.file_type) IS
    
        CURSOR cur_filename IS
        SELECT
            sys_context('USERENV', 'MODULE')
        FROM
            dual;
  
        CURSOR cur_directory IS
        SELECT
            directory_path
        FROM
            dba_directories
        WHERE
            directory_name = gv_directory;
    
        v_context                 VARCHAR2(100);
        v_directory_path          VARCHAR2(2000);
        v_file_name               VARCHAR2(2000);
        ln_org_id                 NUMBER := 0;
        i_posn                    NUMBER := 0;
    BEGIN
        SELECT organization_id INTO ln_org_id FROM hr_operating_units WHERE name = 'CBCL Operating Unit';
    
        dbms_application_info.set_client_info(ln_org_id);

        -----------------------------------------------------------------------------
        -- Set applications context if not already set.
        -----------------------------------------------------------------------------
        v_context := p010_set_context(p_username, p_responsibility_name);
        IF v_context = 'F' THEN
            dbms_output.put_line('Error while setting the context');
        END IF;

        dbms_output.disable;
        dbms_output.enable(100000);

        p_input_file := utl_file.fopen(p_directory, p_datafile, 'r');
    
        OPEN cur_filename;
        FETCH cur_filename INTO v_file_name;
        CLOSE cur_filename;

        i_posn := Instr(v_file_name, '/', -1);
        IF i_posn > 0 THEN
            v_file_name := Substr(v_file_name, i_posn + 1, Length(v_file_name) - i_posn);
        END IF;
--    dbms_output.put_line('+----------------------------- Running XXCRTRCT.sql -----------------------------+');
        dbms_output.put_line(c_line_separator);
        dbms_output.put_line('+- ' || Rpad('Script: ' || v_file_name || ' ', 78, '-') || '+');

        OPEN cur_directory;
        FETCH cur_directory INTO v_directory_path;
        CLOSE cur_directory;
    
        dbms_output.put_line('+- ' || Rpad('Dir: ' || v_directory_path || ' ', 78, '-') || '+');
        dbms_output.put_line('+- ' || Rpad('Data file: ' || p_datafile || ' opened ', 78, '-') || '+');
        dbms_output.put_line(c_line_separator);

        SELECT
            value
        INTO
            gv_dest_dir
        FROM
            v$parameter
        WHERE
            name = 'utl_file_dir';
    
        dbms_application_info.set_client_info(ln_org_id);

        arp_global.init_global;
        arp_standard.init_standard;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = '-29283' THEN
                dbms_output.put_line('File "' || p_datafile || '" could not be opened or operated on as requested');
            END IF;
        dbms_output.put_line('Exception occurred in p020_initialize');
        dbms_output.put_line(SQLERRM);
  END p020_initialize;

  
    -------------------------------------------------------------------------------
    -- Given the input line, extract and return the next leading field from the line
    -- Trim leading and trailing double quotation marks ("), if not comma-separated
    -------------------------------------------------------------------------------
    FUNCTION p040_parse_next_value(p_input_line IN OUT VARCHAR2) RETURN VARCHAR2 IS
        lv_value VARCHAR2(255);
        ln_posn  NUMBER;
    BEGIN

        -- get next value up to the next separator
        ln_posn := instr(p_input_line, c_comma) - 1;
        IF ln_posn >= 0 THEN
            lv_value := substr(p_input_line, 1, ln_posn);
        ELSIF ln_posn < 0 THEN
            lv_value := substr(p_input_line, 1, Length(p_input_line));
        ELSE
            lv_value := '';
        END IF;
        
        -- if data file is comma-separated, if extracted token (lv_value) begins with ", remove it
        IF (substr(lv_value, 1, 1) = '"') THEN
            lv_value := substr(lv_value, 2, length(lv_value) - 1);
        END IF;
        
        -- if data file is comma-separated, if extracted token (lv_value) ends with ", remove it
        IF (substr(lv_value, -1, 1) = '"') THEN
            lv_value := substr(lv_value, 1, length(lv_value) - 1);
        END IF;
        
        -- remove parsed token from beginning of input line, to return
        IF Instr(p_input_line, c_comma) > 0 THEN
            p_input_line := Substr(p_input_line, Instr(p_input_line, c_comma) + 1);
        END IF;
        
        RETURN Trim(lv_value);  -- changed by remove trailing spaces
  EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line('Exception occurred in p040_parse_next_value');
        dbms_output.put_line('p_input_line: ' || p_input_line);
        dbms_output.put_line('lv_value     : ' || lv_value);
        dbms_output.put_line(SQLERRM);
        RETURN '';
  END p040_parse_next_value;


    -------------------------------------------------------------------------------
    -- parse one record of input data
    -- start from the second column, as the first column was already read
    -------------------------------------------------------------------------------
    PROCEDURE p070_parse_one_record(p_input_line IN OUT VARCHAR2) IS
    BEGIN
        v_customer_num := p040_parse_next_value(p_input_line);
        dbms_output.put_line('Finished parsing input line ' || n_total_rows || ':');
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p070_parse_one_record');
            dbms_output.put_line(SQLERRM);
    END p070_parse_one_record;


    -----------------------------------------------------------------------------
    -- Convert string from 'rrrr-mm-dd hh24:mi:ss' format to DATE type
    -- Excel CSV files store dates in that format e.g. 2021-11-30T14:47:17.513
    -----------------------------------------------------------------------------
    PROCEDURE p110_convert_all_dates(p_old_date IN VARCHAR2, p_new_date OUT DATE) IS
        lv_temp_date  VARCHAR2(255);
    BEGIN  
        lv_temp_date := Substr(p_old_date, 1, 10) || ' ' || Substr(p_old_date, 12, 8);
        p_new_date := To_Date(lv_temp_date, 'rrrr-mm-dd hh24:mi:ss');
        
        NULL;
    END p110_convert_all_dates;


    -------------------------------------------------------------------------------
    -- display parsed out columns for current record
    -------------------------------------------------------------------------------
    PROCEDURE p120_display_columns IS
    BEGIN
        dbms_output.put_line('Customer Name      : "' || v_customer_name || '"');
        dbms_output.put_line('Customer Number    : "' || v_customer_num || '"');
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p120_display_columns');
            dbms_output.put_line(SQLERRM);
    END p120_display_columns; 


    -------------------------------------------------------------------------------
    -- populate the record fields that will be used to insert the attribute columns
    -------------------------------------------------------------------------------
    PROCEDURE p130_populate_cust_acct_attr(p_customer_num IN VARCHAR2, p_object_version_number OUT NUMBER, p_cust_account_rec OUT hz_cust_account_v2pub.cust_account_rec_type) IS
        ln_cust_account_id              NUMBER;
    BEGIN
        p_cust_account_rec := NULL;
        SELECT DISTINCT
            hca.cust_account_id,
            hca.object_version_number 
        INTO
            ln_cust_account_id,
            p_object_version_number
        FROM
            apps.hz_cust_accounts         hca
        WHERE
            hca.account_number = p_customer_num;
      
        dbms_output.put_line('p_object_version_number := "' || p_object_version_number || '"');
        p_cust_account_rec.cust_account_id := ln_cust_account_id;
        p_cust_account_rec.status := 'I';
        dbms_output.put_line('p_cust_account_rec.cust_account_id := "' || p_cust_account_rec.cust_account_id || '"');
        dbms_output.put_line('p_object_version_number := "' || p_object_version_number || '"');
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p130_populate_cust_acct_attr');
            dbms_output.put_line(SQLERRM);
    END p130_populate_cust_acct_attr;


    -------------------------------------------------------------------------------
    -- populate the record fields that will be used to insert the attribute columns
    -------------------------------------------------------------------------------
    PROCEDURE p135_populate_cust_acct__site_attr(p_customer_num IN VARCHAR2, p_object_version_number OUT NUMBER, p_cust_acct_site_rec OUT hz_cust_account_site_v2pub.cust_acct_site_rec_type) IS
        ln_cust_acct_site_id              NUMBER;
    BEGIN
        p_cust_acct_site_rec := NULL;
        SELECT DISTINCT
            hcas.cust_acct_site_id,
            hcas.object_version_number 
        INTO
            ln_cust_acct_site_id,
            p_object_version_number
        FROM
            apps.hz_cust_accounts           hca,
            apps.hz_cust_acct_sites_all     hcas
        WHERE
            hca.account_number = p_customer_num
        AND hca.cust_account_id = hcas.cust_account_id;
      
        dbms_output.put_line('p_object_version_number := "' || p_object_version_number || '"');
        p_cust_acct_site_rec.cust_acct_site_id := ln_cust_acct_site_id;
        p_cust_acct_site_rec.status := 'I';
        p_object_version_number := NVL(p_object_version_number, 0); -- + 1;
        
        dbms_output.put_line('p_cust_acct_site_rec.cust_acct_site_id := "' || p_cust_acct_site_rec.cust_acct_site_id || '"');
        p_cust_acct_site_rec.status := 'I';
        dbms_output.put_line('p_object_version_number := "' || p_object_version_number || '"');
        
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p130_populate_cust_acct_attr');
            dbms_output.put_line(SQLERRM);
    END p135_populate_cust_acct__site_attr;


    -----------------------------------------------------------------------------
    -- print status information about ar_receipt_api_pub procedure call
    -----------------------------------------------------------------------------
    PROCEDURE p150_print_status_info(p_return_status IN VARCHAR2, p_msg_count IN NUMBER, p_msg_data IN OUT VARCHAR2, p_customer_num IN VARCHAR2, p_status IN VARCHAR2, p_total_successful IN OUT NUMBER) IS
        v_count                    NUMBER := 0;
    BEGIN
        dbms_output.put_line(gv_input_line);
        dbms_output.put_line('****************************');
        dbms_output.put_line('Processed ' || p_status);
        dbms_output.put_line('Output information... ');
        dbms_output.put_line('x_return_status : ' || p_return_status);
        dbms_output.put_line('x_msg_count     : ' ||p_msg_count);
        dbms_output.put_line('x_msg_data      : ' ||p_msg_data);
        dbms_output.put_line('****************************');
  
        IF p_return_status = FND_API.G_RET_STS_SUCCESS THEN
            p_total_successful := p_total_successful + 1;
            dbms_output.put_line('Customer Number '|| p_customer_num || ' updated successfully');
            dbms_output.new_line;
        ELSE
            IF p_msg_count = 1 THEN
                dbms_output.put_line('l_msg_data: '|| p_msg_data);
            ELSIF p_msg_count > 1 THEN
                LOOP
                    v_count := v_count + 1;
                    p_msg_data := fnd_msg_pub.GET(fnd_msg_pub.g_next, fnd_api.g_false);
                    IF p_msg_data IS NULL THEN
                        EXIT;
                    END IF;
                    dbms_output.put_line('Message ' || v_count ||': '||p_msg_data);
                END LOOP;
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p150_print_status_info');
            dbms_output.put_line(SQLERRM);
  END p150_print_status_info;

  
    -----------------------------------------------------------------------------
    -- commit transactions (:1 = first parameter: commit (Y/N)
    -----------------------------------------------------------------------------
    PROCEDURE p160_commit_transactions(p_commit IN VARCHAR2) IS
    BEGIN
        dbms_output.put_line(c_line_separator);
        IF Upper(p_commit) = 'Y' THEN
            dbms_output.put_line('Commit flag = "' || p_commit || '", committing all receipt transactions...');
            COMMIT;
        ELSE
            dbms_output.put_line('Commit flag = "' || p_commit || '", rolling back all receipt transactions...');
            ROLLBACK;    
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p160_commit_transactions');
            dbms_output.put_line(SQLERRM);
    END p160_commit_transactions;


    -----------------------------------------------------------------------------
    -- print summary after processing all rows
    -----------------------------------------------------------------------------
    PROCEDURE p170_print_summary(p_total_rows IN NUMBER, p_total_successful IN NUMBER, p_datafile IN VARCHAR2) IS
    BEGIN
        dbms_output.put_line(c_line_separator);
        dbms_output.put_line('Total Records Read   : ' || p_total_rows);
        dbms_output.put_line('Total Records Valid  : ' || p_total_successful);
        dbms_output.put_line('Data file ' || p_datafile || ' closed');
        dbms_output.put_line('Load script is completed');
        dbms_output.put_line(c_line_separator);
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p170_print_summary');
            dbms_output.put_line(SQLERRM);
    END p170_print_summary;


/* main driver */
BEGIN
      -------------------------------------------------------------------------------
      -- set up client info, passing org_id = 101
      -------------------------------------------------------------------------------
      p020_initialize(c_username, c_responsibility_name, gv_directory, gv_datafile, input_file);

    -----------------------------------------------------------------------------
    -- set applications context if not already set
    -----------------------------------------------------------------------------
--    v_context := p010_set_context(c_username, c_responsibility_name);
--    IF v_context = 'F' THEN
--        dbms_output.put_line('Error while setting the context');
--        RETURN;
--    END IF;

    LOOP
        -----------------------------------------------------------------------------
        -- Read line of data from data file into l_input_line, exit when no data found
        -----------------------------------------------------------------------------
        gv_input_line := '';
        l_input_line := '';
        BEGIN
            utl_file.get_line(input_file, l_input_line);
            l_input_line := TRIM(REPLACE(REPLACE(l_input_line, CHR(10), ' '), CHR(13), ' ')); -- remove CRLF
            -- l_input_line := Trim(Chr(13) FROM l_input_line); -- trim out trailing CR character
            n_total_rows := n_total_rows + 1;
            gv_input_line := l_input_line;
            EXCEPTION WHEN no_data_found THEN EXIT;  -- exit loop
        END;

        -----------------------------------------------------------------------------
        -- Parse input data line and store each field in a separate variable
        -----------------------------------------------------------------------------
        v_customer_name := p040_parse_next_value(l_input_line);

        -----------------------------------------------------------------------------
        -- Check if first line of data is a header line
        -- If there is a header line in the data file, read the header line and discard
        -----------------------------------------------------------------------------
        IF Upper(v_customer_name) = 'CUSTOMER NAME' OR Upper(v_customer_name) = 'SALES CONTRACTORS' OR v_customer_name IS NULL THEN -- or n_total_rows > 10 THEN
            CONTINUE;
        END IF;
    
        -----------------------------------------------------------------------------
        -- parse one record of input data
        -----------------------------------------------------------------------------
        p070_parse_one_record(l_input_line);

        -----------------------------------------------------------------------------
        -- if debugging is yes, display parsed out columns for current record
        -----------------------------------------------------------------------------
        p120_display_columns;

        -----------------------------------------------------------------------------
        -- call the "create_and_apply" procedure to apply receipt
        -- n.b. KFTL has never used apply on account (create_apply_on_acc) (QA)
        -- if invoice number/transaction number is not null, then use create_and_apply
        -- if transaction number is null, then use create_apply_on_acc
        -----------------------------------------------------------------------------
        IF Length(v_customer_name) > 0 THEN

/*    
        -- first, update customer account site
        p135_populate_cust_acct__site_attr(v_customer_num, ln_cas_object_version_number, v_cust_acct_site_rec);
        hz_cust_account_site_v2pub.update_cust_acct_site (
            p_init_msg_list => fnd_api.g_true, 
            p_cust_acct_site_rec => v_cust_acct_site_rec, 
            p_object_version_number => ln_cas_object_version_number, 
            x_return_status => l_return_status, 
            x_msg_count => l_msg_count,
            x_msg_data => l_msg_data
        );
        p150_print_status_info(l_return_status, l_msg_count, l_msg_data, v_customer_num, 'customer site account', n_total_successful);
*/

        -- next, update customer account
        p130_populate_cust_acct_attr(v_customer_num, ln_ca_object_version_number, v_cust_account_rec);    
        hz_cust_account_v2pub.update_cust_account (
            p_init_msg_list => fnd_api.g_true, 
            p_cust_account_rec => v_cust_account_rec, 
            p_object_version_number => ln_ca_object_version_number, 
            x_return_status => l_return_status, 
            x_msg_count => l_msg_count,
            x_msg_data => l_msg_data
        );
        p150_print_status_info(l_return_status, l_msg_count, l_msg_data, v_customer_num, 'customer account', n_total_successful);
        
        END IF;    
    END LOOP;

    utl_file.fclose(input_file);

    -----------------------------------------------------------------------------
    -- commit or rollback transactions (:1 = first parameter: commit (Y/N)
    -----------------------------------------------------------------------------
    p160_commit_transactions(gv_commit);
  
    -----------------------------------------------------------------------------
    -- print summary of data load (above)
    -----------------------------------------------------------------------------
    p170_print_summary(n_total_rows, n_total_successful, gv_datafile);  
  
EXCEPTION
    WHEN OTHERS THEN
        dbms_output.put_line('Exception occurred in main driver');
        dbms_output.put_line(SQLERRM);
END;
/
    -- Setting the Context
--    p010_set_context(c_username, c_responsibility_name);
--;
--    mo_global.init('AR');
--    fnd_global.apps_initialize(user_id => 1318, resp_id => 50559, resp_appl_id => 222);
--
--    mo_global.set_policy_context('S', 204);
--    fnd_global.set_nls_context('AMERICAN');

/*
    -- Initializing the Mandatory API parameters
    p_cust_account_rec.cust_account_id := 150734;
    p_cust_account_rec.customer_type := 'R';  -- Should be available under the lookup_type “CUSTOMER_TYPE”

    p_cust_account_rec.account_name := 'TCA – Account';
    ln_ca_object_version_number := 1;
    dbms_output.put_line('Calling the API hz_cust_account_v2pub.update_cust_account');
    hz_cust_account_v2pub.update_cust_account(
        p_init_msg_list => fnd_api.g_true, 
        p_cust_account_rec => p_cust_account_rec, 
        p_object_version_number => ln_ca_object_version_number, 
        x_return_status => x_return_status, 
        x_msg_count => x_msg_count,
        x_msg_data => x_msg_data
    );

    IF x_return_status = fnd_api.g_ret_sts_success THEN
        COMMIT;
        dbms_output.put_line('Updation of Customer Account is Successful ');
        dbms_output.put_line('Output information ….');
        dbms_output.put_line('Object Version Number =' || ln_ca_object_version_number);
    ELSE
        dbms_output.put_line('Updation of Customer Account got failed:' || x_msg_data);
        ROLLBACK;
        FOR i IN 1..x_msg_count LOOP
            x_msg_data := fnd_msg_pub.get(p_msg_index => i, p_encoded => 'F');
            dbms_output.put_line(i || ') ' || x_msg_data);
        END LOOP;
    END IF;
    dbms_output.put_line('completion OF api');
*/
// END;
// /