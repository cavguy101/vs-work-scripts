--------------------------------------------------------------------------------
-- xxcrtrct.sql
-- Custom script to load receipts from N4 into E-Business Suite
-- Calls the ar_receipt_api_pub.create_and_apply procedure
-- Data is read from the data file and loaded into EBS
--------------------------------------------------------------------------------
-- Parameter & 1 in the script is whether to commit/rollback (Y or N)
-- Parameter & 2 is the filename (optional)
-- Parameter & 3 is the database directory (optional)
--------------------------------------------------------------------------------
-- Ver  Date       Modified by   Change
-- 1    27-MAR-19  vseeram       Created
-- 2    03-JUL-19  vseeram       Saved dates in DATE variable rather than VARCHAR2
-- 3    06-AUG-19  vseeram       Remove filename from lookup values; refactor code
-- 4    20-AUG-19  vseeram       Moved commit to outside for loop in p190
-- 5    26-AUG-19  vseeram       Minor code fixes for USD receipts
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE 100000;
SET APPINFO ON
SET TRIMSPOOL ON
SET FEEDBACK ON

--------------------------------------------------------------------------------
-- SET APPINFO ON         -- to be able to get script name
--------------------------------------------------------------------------------
-- Assume that the database directory APPS_DATA_FILE_DIR exists in E-Business Suite
--------------------------------------------------------------------------------
-- Data file sent by William's program may retain header row, or it may be removed
--------------------------------------------------------------------------------
-- The return status (x_return_status) of the API informs the caller about the result of the operation (or operations) 
-- performed by the API. The different possible values for an API return status are:
-- 1. Success (FND_API.G_RET_STS_SUCCESS)
-- 2. Error (FND_API.G_RET_STS_ERROR)
-- 3. Unexpected error (FND_API.G_RET_STS_UNEXP_ERROR)
--------------------------------------------------------------------------------
-- To view receipts on TEST EBS instance:
--   Receivables Manager > Receipts > Receipts
--------------------------------------------------------------------------------
-- *** Error: Receipt method identifier is invalid
-- Cause: Bank wasn't assigned to payment method in receipt classes
-- Solution: Add bank to payment method using the following navigation
-- Receivables Manager > Setup > Receipts > Receipt Classes
-- Query Receipt Class, select Payment Method, and click Bank Accounts
-- For JMD, enter "Bank of Nova Scotia Jamaica Limted", "BNS 988099"
-- Set Effective Date = 01-JAN-2019
--------------------------------------------------------------------------------
-- Receipt API User Notes (documentation):
-- https://docs.oracle.com/cd/E18727_01/doc.121/e13512/T447348T399045.htm
--------------------------------------------------------------------------------
-- Receivables Lookup:
--   Receivables Manager > Setup > System > Quick Codes > Receivables
--------------------------------------------------------------------------------
-- Descriptive Flexfield Segments:
--   Receivables Manager > Financials > Flexfields > Descriptive > Segments
--   Query: Application: Receivables, Title: Receipt Information
--------------------------------------------------------------------------------


DECLARE
    -- initialize constants
    c_username            CONSTANT VARCHAR2(30) := 'SYSADMIN';
    c_responsibility_name CONSTANT VARCHAR2(50) := 'Receivables Manager';
    c_org_id              CONSTANT NUMBER := 101;
    c_comma               CONSTANT VARCHAR2(1) := ','; -- separator for comma-separated values (CSV) datafiles
    c_tab                 CONSTANT VARCHAR2(1) := chr(9);  -- separator for tab-separated values (TSV) datafiles
    c_separator           CONSTANT VARCHAR2(1) := c_tab; -- ',';  -- separator is either a comma or a tab (Chr(9))
    c_yes                 CONSTANT VARCHAR2(1) := 'Y';  -- 'Y'
    c_no                  CONSTANT VARCHAR2(1) := 'N';  -- 'Y'
    c_debug_flag          CONSTANT VARCHAR2(1) := ' '; -- set to c_yes to turn on debugging
    c_line_separator      CONSTANT VARCHAR2(99) := rpad('+', 81, '-') || '+ ';
  
    -- initialize global variables/parameters
    gv_commit             VARCHAR2(1) := upper(nvl(('&1'), c_no));
    gv_datafile           VARCHAR2(255) := nvl('&2', 'XXCRTRCT.dat');
    gv_directory          VARCHAR2(255) := nvl('&3', 'APPS_DATA_FILE_DIR');
    gv_input_line         VARCHAR2(2000);
    input_file            utl_file.file_type;
    n_total_rows          NUMBER := 0;
    n_total_successful    NUMBER := 0;
    l_input_line          VARCHAR2(2000);

    -- File layout of the details lines
    -- Payment Method, Currency Code,Exchange Rate,Rate Type,Receipt Amount,Receipt Number,Receipt Date,Accounting Date,Customer Number,Customer Name,Remittance Bank Account,Transaction Number,Amount Applied,Applied Date,TARIFF DETAILS,Exchange Rate,Tariff Rate Currency,Tariff Rate,Bill of Laden,B.O.L.Suffix,Container Number,Reference Number,Conatiner LGTH,Receipt Type,CHEQUE INFO,Bank Drawn On,Cheque Number,Cheque Date

    TYPE attribute_rec_type IS RECORD (
        attribute_category VARCHAR2(30) DEFAULT NULL,
        attribute1         VARCHAR2(150) DEFAULT NULL,
        attribute2         VARCHAR2(150),
        attribute3         VARCHAR2(150),
        attribute4         VARCHAR2(150),
        attribute5         VARCHAR2(150),
        attribute6         VARCHAR2(150),
        attribute7         VARCHAR2(150),
        attribute8         VARCHAR2(150),
        attribute9         VARCHAR2(150),
        attribute10        VARCHAR2(150),
        attribute11        VARCHAR2(150),
        attribute12        VARCHAR2(150),
        attribute13        VARCHAR2(150),
        attribute14        VARCHAR2(150),
        attribute15        VARCHAR2(150)
    );

    -- variables to store data read from input file
    v_payment_method      VARCHAR2(255);
    v_currency_code       VARCHAR2(255);
    v_exchange_rate       VARCHAR2(255);
    v_rate_type           VARCHAR2(255);
    v_receipt_amount      VARCHAR2(255);
    v_receipt_number      VARCHAR2(255);
    v_receipt_date        VARCHAR2(255);
    v_receipt_date2       DATE; -- Added by VS 03-JUL-19 New variable to store date variables
    v_accounting_date     VARCHAR2(255);
    v_accounting_date2    DATE; -- Added by VS 03-JUL-19 New variable to store date variables
    v_exchange_rate_date  DATE; -- Added by VS 26-AUG-19 To store exchange rate date (previously provided by v_accounting_date2)
    v_customer_number     VARCHAR2(255);
    v_customer_name       VARCHAR2(255);
    v_remittance_acct     VARCHAR2(255);
    v_transaction_number  VARCHAR2(255);
    v_amount_applied      VARCHAR2(255);
    v_apply_date          VARCHAR2(255);
    v_apply_date2         DATE; -- Added by VS 03-JUL-19 New variable to store date variables
    v_tariff_details      VARCHAR2(255);
    v_exchange_rate2      VARCHAR2(255);
    v_tariff_rate_curr    VARCHAR2(255);
    v_tariff_rate         VARCHAR2(255);
    v_bill_of_laden       VARCHAR2(255);
    v_bol_suffix          VARCHAR2(255);
    v_container_number    VARCHAR2(255);
    v_reference_number    VARCHAR2(255);
    v_container_lgth      VARCHAR2(255);
    v_receipt_type        VARCHAR2(255);
    v_cheque_info         VARCHAR2(255);
    v_bank_drawn_on       VARCHAR2(255);
    v_cheque_number       VARCHAR2(255);
    v_cheque_date         VARCHAR2(255);
    v_payment_ind         VARCHAR2(255);
    v_receipt_method_id   NUMBER;  -- Was VARCHAR2(255)
    v_customer_trx_id     NUMBER;  -- Was VARCHAR2(2000);
    v_attribute_rec       ar_receipt_api_pub.attribute_rec_type;

    -- variables to store returned values from API call
    l_return_status       VARCHAR2(10);
    l_msg_count           NUMBER := 0;
    l_msg_data            VARCHAR2(2000);
    l_cash_receipt_id     NUMBER := 0;


    --------------------------------------------------------------------------------
    -- function to set the application context before calling the API call
    -- ar_receipt_api_pub.create_and_apply
    --------------------------------------------------------------------------------
    FUNCTION p010_set_context (
        i_user_name IN VARCHAR2,
        i_resp_name IN VARCHAR2,
        i_org_id    IN NUMBER
    ) RETURN VARCHAR2 IS

        v_user_id      NUMBER;
        v_resp_id      NUMBER;
        v_resp_appl_id NUMBER;
        v_lang         VARCHAR2(100);
        v_session_lang VARCHAR2(100) := fnd_global.current_language;
        v_return       VARCHAR2(10) := 'T';
        v_nls_lang     VARCHAR2(100);
        v_org_id       NUMBER := i_org_id;

        /* Cursor to get the user id information based on the input user name */
        CURSOR cur_user IS
        SELECT
            user_id
        FROM
            fnd_user
        WHERE
            user_name = i_user_name;

        /* Cursor to get the responsibility information */
        CURSOR cur_resp IS
        SELECT
            responsibility_id,
            application_id,
            language
        FROM
            fnd_responsibility_tl
        WHERE
            responsibility_name = i_resp_name;

        /* Cursor to get the nls language information for setting the language context */
        CURSOR cur_lang (
            p_lang_code VARCHAR2
        ) IS
        SELECT
            nls_language
        FROM
            fnd_languages
        WHERE
            language_code = p_lang_code;

    BEGIN
        /* To get the user id details */
        OPEN cur_user;
        FETCH cur_user INTO v_user_id;
        IF cur_user%notfound THEN
            v_return := 'F';
        END IF; --IF cur_user%NOTFOUND
        CLOSE cur_user;

        /* To get the responsibility and responsibility application id */
        OPEN cur_resp;
        FETCH cur_resp INTO
            v_resp_id,
            v_resp_appl_id,
            v_lang;
        IF cur_resp%notfound THEN
            v_return := 'F';
        END IF; --IF cur_resp%NOTFOUND
        CLOSE cur_resp;

        /* Setting the oracle applications context for the particular session */
        fnd_global.apps_initialize(user_id => v_user_id, resp_id => v_resp_id, resp_appl_id => v_resp_appl_id);

        /* Setting the org context for the particular session */
        mo_global.set_policy_context('S', v_org_id);

        /* setting the nls context for the particular session */
        IF v_session_lang != v_lang THEN
            OPEN cur_lang(v_lang);
            FETCH cur_lang INTO v_nls_lang;
            CLOSE cur_lang;
            fnd_global.set_nls_context(v_nls_lang);
        END IF; --IF v_session_lang != v_lang

        RETURN v_return;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p010_set_context');
            dbms_output.put_line(sqlerrm);
            RETURN 'F';
    END p010_set_context;

    ----------------------------------------------------------------------------
    -- initialize environment before running code
    ----------------------------------------------------------------------------
    PROCEDURE p020_initialize (
        p_org_id              IN NUMBER,
        p_username            IN VARCHAR2,
        p_responsibility_name IN VARCHAR2,
        p_directory           IN VARCHAR2,
        p_datafile            IN VARCHAR2,
        p_input_file          OUT utl_file.file_type
    ) IS

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

        v_context        VARCHAR2(100);
        v_directory_path VARCHAR2(2000);
        v_file_name      VARCHAR2(2000);
        i_posn           NUMBER := 0;
    BEGIN
        dbms_application_info.set_client_info(p_org_id);

        ------------------------------------------------------------------------
        -- Set applications context if not already set.
        ------------------------------------------------------------------------
        v_context := p010_set_context(p_username, p_responsibility_name, p_org_id);
        IF v_context = 'F' THEN
            dbms_output.put_line('Error while setting the context');
        END IF;
        dbms_output.disable;
        dbms_output.enable(100000);
        p_input_file := utl_file.fopen(p_directory, p_datafile, 'r');
        OPEN cur_filename;
        FETCH cur_filename INTO v_file_name;
        CLOSE cur_filename;
        i_posn := instr(v_file_name, '/', -1);
        IF i_posn > 0 THEN
            v_file_name := substr(v_file_name, i_posn + 1, length(v_file_name) - i_posn);
        END IF;
--    dbms_output.put_line('+----------------------------- Running XXCRTRCT.sql -----------------------------+');
        dbms_output.put_line(c_line_separator);
        dbms_output.put_line('+- ' || rpad('Script: ' || v_file_name || ' ', 78, '-') || '+');

        OPEN cur_directory;
        FETCH cur_directory INTO v_directory_path;
        CLOSE cur_directory;
        dbms_output.put_line('+- ' || rpad('Dir: ' || v_directory_path || ' ', 78, '-') || '+');

        dbms_output.put_line('+- ' || rpad('Data file: ' || p_datafile || ' opened ', 78, '-') || '+');

        dbms_output.put_line(c_line_separator);
        dbms_application_info.set_client_info(p_org_id);
        arp_global.init_global;
        arp_standard.init_standard;
    EXCEPTION
        WHEN OTHERS THEN
            IF sqlcode = '-29283' THEN
                dbms_output.put_line('File "' || p_datafile || '" could not be opened or operated on as requested');
            END IF;

            dbms_output.put_line('Exception occurred in p020_initialize');
            dbms_output.put_line(sqlerrm);
    END p020_initialize;
  
    --------------------------------------------------------------------------------
    -- print output header line for each row
    --------------------------------------------------------------------------------
    PROCEDURE p030_print_header_line (
        p_total_rows  IN OUT NUMBER,
        p_input_line  IN VARCHAR2,
        p_input_line2 OUT VARCHAR2
    ) IS
    BEGIN
        p_total_rows := p_total_rows + 1;
        dbms_output.put_line(' ');
        dbms_output.put_line(c_line_separator);
        dbms_output.put_line(' ');
        p_input_line2 := p_input_line;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p030_print_header_line');
            dbms_output.put_line(sqlerrm);
    END p030_print_header_line;
  
    --------------------------------------------------------------------------------
    -- Given the input line, extract and return the next leading field from the line
    -- Trim leading and trailing double quotation marks ("), if not comma-separated
    --------------------------------------------------------------------------------
    FUNCTION p040_parse_next_value (
        p_input_line IN OUT VARCHAR2
    ) RETURN VARCHAR2 IS
        lv_value VARCHAR2(255);
    BEGIN
        -- get next value up to the next separator
        lv_value := substr(p_input_line, 1, instr(p_input_line, c_separator) - 1);

        -- if data file is comma-separated, if extracted token (lv_value) begins with ", remove it
        IF
            ( c_separator = c_comma )
            AND ( substr(lv_value, 1, 1) = '"' )
        THEN
            lv_value := substr(lv_value, 2, length(lv_value) - 1);
        END IF;

        -- if data file is comma-separated, if extracted token (lv_value) ends with ", remove it
        IF
            ( c_separator = c_comma )
            AND ( substr(lv_value, -1, 1) = '"' )
        THEN
            lv_value := substr(lv_value, 1, length(lv_value) - 1);
        END IF;

        -- remove parsed token from beginning of input line, to return
        IF instr(p_input_line, c_separator) > 0 THEN
            p_input_line := substr(p_input_line, instr(p_input_line, c_separator) + 1);
        END IF;

        RETURN lv_value;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p040_parse_next_value');
            dbms_output.put_line('p_input_line: ' || p_input_line);
            dbms_output.put_line('lv_value     : ' || lv_value);
            dbms_output.put_line(sqlerrm);
            RETURN '';
    END p040_parse_next_value;
  
    --------------------------------------------------------------------------------
    -- returns TRUE if c_debug_flag = c_yes (i.e. debugging is yes), or FALSE otherwise
    --------------------------------------------------------------------------------
    FUNCTION p050_debugging_is_yes RETURN BOOLEAN IS
    BEGIN
        RETURN ( c_debug_flag = c_yes );
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p050_debugging_is_yes');
            dbms_output.put_line(sqlerrm);
    END;
  
    --------------------------------------------------------------------------------
    -- if debugging is turned on, print a debugging message to the console
    --------------------------------------------------------------------------------
    PROCEDURE p060_debug_print (
        p_text IN VARCHAR2
    ) IS
    BEGIN
        IF p050_debugging_is_yes THEN
            dbms_output.put_line(p_text);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p060_debug_print');
            dbms_output.put_line(sqlerrm);
    END p060_debug_print;

    --------------------------------------------------------------------------------
    -- parse one record of input data
    --------------------------------------------------------------------------------
    PROCEDURE p070_parse_one_record (
        p_input_line IN OUT VARCHAR2
    ) IS
    BEGIN
        v_currency_code := p040_parse_next_value(p_input_line);
        v_exchange_rate := p040_parse_next_value(p_input_line);
        v_rate_type := p040_parse_next_value(p_input_line);
        v_receipt_amount := p040_parse_next_value(p_input_line);
        v_receipt_number := p040_parse_next_value(p_input_line);
        v_receipt_date := p040_parse_next_value(p_input_line);
        v_accounting_date := p040_parse_next_value(p_input_line);
        v_customer_number := p040_parse_next_value(p_input_line);
        v_customer_name := p040_parse_next_value(p_input_line);
        v_remittance_acct := p040_parse_next_value(p_input_line);
        v_transaction_number := p040_parse_next_value(p_input_line);
        v_amount_applied := p040_parse_next_value(p_input_line);
        v_apply_date := p040_parse_next_value(p_input_line);
        v_tariff_details := p040_parse_next_value(p_input_line);
        v_exchange_rate2 := p040_parse_next_value(p_input_line);
        v_tariff_rate_curr := p040_parse_next_value(p_input_line);
        v_tariff_rate := p040_parse_next_value(p_input_line);
        v_bill_of_laden := p040_parse_next_value(p_input_line);
        v_bol_suffix := p040_parse_next_value(p_input_line);
        v_container_number := p040_parse_next_value(p_input_line);
        v_reference_number := p040_parse_next_value(p_input_line);
        v_container_lgth := p040_parse_next_value(p_input_line);
        v_receipt_type := p040_parse_next_value(p_input_line);
        v_cheque_info := p040_parse_next_value(p_input_line);
        v_bank_drawn_on := p040_parse_next_value(p_input_line);
        v_cheque_number := p040_parse_next_value(p_input_line);
        v_cheque_date := p040_parse_next_value(p_input_line);
        v_payment_ind := p040_parse_next_value(p_input_line);
    
        p060_debug_print('Finished parsing input line');
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p070_parse_one_record');
            dbms_output.put_line(sqlerrm);
    END p070_parse_one_record;

    -----------------------------------------------------------------------------
    -- Given payment method, extract the receipt method id
    -----------------------------------------------------------------------------   
    PROCEDURE p080_get_receipt_method_id (
        p_payment_method    IN VARCHAR2,
        p_receipt_method_id OUT NUMBER
    ) IS
    BEGIN
        p_receipt_method_id := TO_NUMBER ( p_payment_method );
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p080_get_receipt_method_id');
            dbms_output.put_line(sqlerrm);
    END p080_get_receipt_method_id;


    -----------------------------------------------------------------------------
    -- Given transaction number, extract the corresponding customer trx id
    -----------------------------------------------------------------------------
    PROCEDURE p090_get_customer_trx_id (
        p_transaction_number IN VARCHAR2,
        p_customer_trx_id    OUT NUMBER
    ) IS
    BEGIN
        p060_debug_print('Checking customer trx ID for transaction number '
                         || p_transaction_number || '...');
        p_customer_trx_id := NULL;
        IF length(p_transaction_number) > 0 THEN
            SELECT
                MAX(rcta.customer_trx_id)
            INTO p_customer_trx_id
            FROM
                ra_customer_trx_all rcta
            WHERE
                    1 = 1
                AND rcta.trx_number = p_transaction_number;

        END IF;

        p060_debug_print('Finished checking customer trx ID...');
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p090_get_customer_trx_id');
            dbms_output.put_line(sqlerrm);
    END p090_get_customer_trx_id;


    -----------------------------------------------------------------------------
    -- Convert string from 'rrrr-mm-dd hh24:mi:ss' format to DATE type
    -----------------------------------------------------------------------------
    PROCEDURE p100_convert_varchar2_to_date (
        p_old_date IN VARCHAR2,
        p_new_date OUT DATE
    ) IS
    BEGIN
        p_new_date := TO_DATE ( p_old_date, 'rrrr-mm-dd hh24:mi:ss' );
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p100_convert_varchar2_to_date');
            dbms_output.put_line(sqlerrm);
    END p100_convert_varchar2_to_date;


    -----------------------------------------------------------------------------
    -- Reformat date columns from input file into date variable (DD-MON-RR format)
    -- Modified by VS 03-JUL-19 Changed date variables from VARCHAR2 to DATE
    -- As recommended by WBhola
    -----------------------------------------------------------------------------
    PROCEDURE p110_convert_all_dates IS
    BEGIN  
    -- v_receipt_date2 := To_Date(v_receipt_date, 'rrrr-mm-dd hh24:mi:ss');
    -- v_accounting_date2 := To_Date(v_accounting_date, 'rrrr-mm-dd hh24:mi:ss');
    -- v_apply_date2 := To_Date(v_apply_date, 'rrrr-mm-dd hh24:mi:ss');
        p100_convert_varchar2_to_date(v_receipt_date, v_receipt_date2);
        p100_convert_varchar2_to_date(v_accounting_date, v_accounting_date2);
        p100_convert_varchar2_to_date(v_apply_date, v_apply_date2);
        v_exchange_rate_date := v_accounting_date2;
    END p110_convert_all_dates;


    -----------------------------------------------------------------------------
    -- Set the v_exchange_rate, v_rate_type and v_exchange_rate_date to null
    -- if v_currency_code = 'USD' 
    -- Added by VS 27-AUG-19 Set currency exchange fields to '' if currency is USD
    -----------------------------------------------------------------------------
    PROCEDURE p115_set_usd_exchange_fields IS
    BEGIN
        IF v_currency_code = 'USD' THEN
            v_exchange_rate := '';
            v_rate_type := '';
            v_exchange_rate_date := '';
        END IF;
    END p115_set_usd_exchange_fields;


    --------------------------------------------------------------------------------
    -- display parsed out columns for current record
    --------------------------------------------------------------------------------
    PROCEDURE p120_display_columns IS
    BEGIN
        IF p050_debugging_is_yes THEN
            dbms_output.put_line('PAYMENT METHOD     : "' || v_payment_method || '"');
            dbms_output.put_line('CURRENCY CODE      : "' || v_currency_code || '"');
            dbms_output.put_line('EXCHANGE RATE      : "' || v_exchange_rate || '"');
            dbms_output.put_line('RATE TYPE          : "' || v_rate_type || '"');
            dbms_output.put_line('RECEIPT AMOUNT     : "' || v_receipt_amount || '"');
            dbms_output.put_line('RECEIPT NUMBER     : "' || v_receipt_number || '"');
            dbms_output.put_line('RECEIPT DATE       : "' || v_receipt_date || '"');
            dbms_output.put_line('ACCOUNTING DATE    : "' || v_accounting_date || '"');
            dbms_output.put_line('CUSTOMER NUMBER    : "' || v_customer_number || '"');
            dbms_output.put_line('CUSTOMER NAME      : "' || v_customer_name || '"');
            dbms_output.put_line('REMITTANCE ACCT    : "' || v_remittance_acct || '"');
            dbms_output.put_line('TRANSACTION NUMBER : "' || v_transaction_number || '"');
            dbms_output.put_line('AMOUNT APPLIED     : "' || v_amount_applied || '"');
            dbms_output.put_line('APPLY DATE         : "' || v_apply_date || '"');
            dbms_output.put_line('TARIFF DETAILS     : "' || v_tariff_details || '"');
            dbms_output.put_line('EXCHANGE RATE2     : "' || v_exchange_rate2 || '"');
            dbms_output.put_line('TARIFF RATE CURR   : "' || v_tariff_rate_curr || '"');
            dbms_output.put_line('BILL OF LADEN      : "' || v_bill_of_laden || '"');
            dbms_output.put_line('BOL SUFFIX         : "' || v_bol_suffix || '"');
            dbms_output.put_line('CONTAINER NUMBER   : "' || v_container_number || '"');
            dbms_output.put_line('REFERENCE NUMBER   : "' || v_reference_number || '"');
            dbms_output.put_line('CONTAINER LENGTH   : "' || v_container_lgth || '"');
            dbms_output.put_line('RECEIPT TYPE       : "' || v_receipt_type || '"');
            dbms_output.put_line('CHEQUE INFO        : "' || v_cheque_info || '"');
            dbms_output.put_line('BANK DRAWN ON      : "' || v_bank_drawn_on || '"');
            dbms_output.put_line('CHEQUE NUMBER      : "' || v_cheque_number || '"');
            dbms_output.put_line('CHEQUE DATE        : "' || v_cheque_date || '"');
            dbms_output.put_line('PAYMENT_IND        : "' || v_payment_ind || '"');
            dbms_output.put_line('RECEIPT METHOD ID  : "' || v_receipt_method_id || '"');
            dbms_output.put_line('CUSTOMER TRX ID    : "' || v_customer_trx_id || '"');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p120_display_columns');
            dbms_output.put_line(sqlerrm);
    END p120_display_columns; 


    --------------------------------------------------------------------------------
    -- populate the record fields that will be used to insert the attribute columns
    --------------------------------------------------------------------------------
    PROCEDURE p130_populate_attributes (
        p_attribute_rec OUT ar_receipt_api_pub.attribute_rec_type
    ) IS
    BEGIN
        p_attribute_rec := NULL;

        -- this assigns the datafile fields to attributes in the order of the descriptive flexfield
        p_attribute_rec.attribute1 := v_exchange_rate2;
        p_attribute_rec.attribute2 := v_tariff_rate_curr;
        p_attribute_rec.attribute3 := v_tariff_details;
        p_attribute_rec.attribute4 := v_bill_of_laden;
        p_attribute_rec.attribute5 := v_bol_suffix;
        p_attribute_rec.attribute6 := v_container_number;
        p_attribute_rec.attribute7 := v_reference_number;
        p_attribute_rec.attribute8 := v_container_lgth;
        p_attribute_rec.attribute9 := v_receipt_type;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p130_populate_attributes');
            dbms_output.put_line(sqlerrm);
    END p130_populate_attributes;

  
    --------------------------------------------------------------------------------
    -- if debugging flag is yes, enable debugging
    --------------------------------------------------------------------------------
    PROCEDURE p140_enable_debugging IS
    BEGIN
        IF p050_debugging_is_yes THEN
            arp_standard.enable_debug;
            arp_standard.enable_file_debug('/usr/tmp', 'xx_debug_' || to_char(sysdate, 'RRRRMMDD') || '.log');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p140_enable_debugging');
            dbms_output.put_line(sqlerrm);
    END p140_enable_debugging;


    -----------------------------------------------------------------------------
    -- print status information about ar_receipt_api_pub procedure call
    -----------------------------------------------------------------------------
    PROCEDURE p150_print_status_info (
        p_return_status    IN VARCHAR2,
        p_msg_count        IN NUMBER,
        p_msg_data         IN OUT VARCHAR2,
        p_cash_receipt_id  IN NUMBER,
        p_receipt_number   IN VARCHAR2,
        p_total_successful IN OUT NUMBER
    ) IS
        v_count NUMBER := 0;
    BEGIN
        IF p_return_status = fnd_api.g_ret_sts_success THEN
            p_total_successful := p_total_successful + 1;
            dbms_output.put_line('Receipt ' || v_receipt_number || ' loaded successfully');
        ELSE
            dbms_output.put_line(gv_input_line);
            dbms_output.put_line('****************************');
            dbms_output.put_line('Output information... ');
            dbms_output.put_line('x_return_status : ' || p_return_status);
            dbms_output.put_line('x_msg_count     : ' || p_msg_count);
            dbms_output.put_line('x_msg_data      : ' || p_msg_data);
            dbms_output.put_line('p_cr_id         : ' || p_cash_receipt_id);
            dbms_output.put_line('****************************');
            IF p_msg_count = 1 THEN
                dbms_output.put_line('l_msg_data: ' || p_msg_data);
            ELSIF p_msg_count > 1 THEN
                LOOP
                    v_count := v_count + 1;
                    p_msg_data := fnd_msg_pub.get(fnd_msg_pub.g_next, fnd_api.g_false);
                    IF p_msg_data IS NULL THEN
                        EXIT;
                    END IF;
                    dbms_output.put_line('Message ' || v_count || ': ' || p_msg_data);
                END LOOP;
            END IF;

        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p150_print_status_info');
            dbms_output.put_line(sqlerrm);
    END p150_print_status_info;

  
  -----------------------------------------------------------------------------
  -- commit transactions (:1 = first parameter: commit (Y/N)
  -----------------------------------------------------------------------------
    PROCEDURE p160_commit_transactions (
        p_commit IN VARCHAR2
    ) IS
    BEGIN
        dbms_output.put_line(c_line_separator);
        IF upper(p_commit) = 'Y' THEN
            dbms_output.put_line('Commit flag = "' || p_commit || '", committing all receipt transactions...');
            COMMIT;
        ELSE
            dbms_output.put_line('Commit flag = "' || p_commit || '", rolling back all receipt transactions...');
            ROLLBACK;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p160_commit_transactions');
            dbms_output.put_line(sqlerrm);
    END p160_commit_transactions;


    -----------------------------------------------------------------------------
    -- print summary after processing all rows
    -----------------------------------------------------------------------------
    PROCEDURE p170_print_summary (
        p_total_rows                    IN NUMBER,
        p_total_successful              IN NUMBER,
        p_datafile                      IN VARCHAR2
    ) IS
    BEGIN
        dbms_output.put_line(c_line_separator);
        dbms_output.put_line('****************************');
        dbms_output.put_line('Total Records Read   : ' || p_total_rows);
        dbms_output.put_line('Total Records Valid  : ' || p_total_successful);
        dbms_output.put_line('Data file ' || p_datafile || ' closed');
        dbms_output.put_line('Load script is completed');
        dbms_output.put_line(c_line_separator);
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p170_print_summary');
            dbms_output.put_line(sqlerrm);
    END p170_print_summary;


    --------------------------------------------------------------------------------
    -- if debugging flag is yes, disable debugging
    --------------------------------------------------------------------------------
    PROCEDURE p180_disable_debugging IS
    BEGIN
        IF p050_debugging_is_yes THEN
            arp_standard.disable_debug;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p180_disable_debugging');
            dbms_output.put_line(sqlerrm);
    END p180_disable_debugging;


    --------------------------------------------------------------------------------
    -- Delete the filename if it exists in the fnd_lookup_values table
    -- https://oracleappsdna.com/2017/02/plsql-script-to-delete-lookup-or-lookup-code/
    -- Receivables Manager > Setup > System > Quick Codes > Receivables
    --------------------------------------------------------------------------------
    PROCEDURE p190_delete_filename_from_flv (
        p_datafile IN VARCHAR2
    ) IS

        CURSOR cur_fnd_lookup_values IS
        SELECT
            flv.lookup_type,
            flv.lookup_code,
            flv.security_group_id,
            flv.view_application_id
        FROM
            applsys.fnd_lookup_values flv
        WHERE
                flv.lookup_type = 'N4_ORA_PAYMENT_FILE_NAME'
            AND flv.lookup_code = p_datafile -- OR flv.meaning = p_datafile OR flv.description = p_datafile);
            ;

    BEGIN
        -- only delete the filename if commit = 'Y'
        IF gv_commit = c_yes THEN
            FOR i IN cur_fnd_lookup_values LOOP
                fnd_lookup_values_pkg.delete_row(
                    x_lookup_type => i.lookup_type, 
                    x_lookup_code => i.lookup_code, 
                    x_security_group_id => i.security_group_id, 
                    x_view_application_id => i.view_application_id
                );
                p060_debug_print('Deleting filename ' || i.lookup_code || '...');
            END LOOP;

            p060_debug_print('Committing...');
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Exception occurred in p190_delete_filename_from_flv');
            dbms_output.put_line(sqlerrm);
    END p190_delete_filename_from_flv;

BEGIN /* main driver */

    --------------------------------------------------------------------------------
    -- set up client info, passing org_id = 101
    --------------------------------------------------------------------------------
    p020_initialize(c_org_id, c_username, c_responsibility_name, gv_directory, gv_datafile, input_file);
    LOOP
        -----------------------------------------------------------------------------
        -- Read line of data from data file into l_input_line, exit when no data found
        -----------------------------------------------------------------------------
        gv_input_line := '';
        l_input_line := '';
        BEGIN
            utl_file.get_line(input_file, l_input_line);
        EXCEPTION
            WHEN no_data_found THEN
                EXIT;  -- exit loop
        END;

        -----------------------------------------------------------------------------
        -- Print output header line
        -----------------------------------------------------------------------------
        p030_print_header_line(n_total_rows, l_input_line, gv_input_line);
  
        -----------------------------------------------------------------------------
        -- Parse input data line and store each field in a separate variable
        -----------------------------------------------------------------------------
        v_payment_method := p040_parse_next_value(l_input_line);
  
        -----------------------------------------------------------------------------
        -- Check if first line of data is a header line
        -- If there is a header line in the data file, read the header line and discard
        -----------------------------------------------------------------------------
        IF upper(v_payment_method) = 'PAYMENT METHOD' THEN -- or n_total_rows > 10 THEN
            CONTINUE;
        END IF;
      
        -----------------------------------------------------------------------------
        -- parse one record of input data
        -----------------------------------------------------------------------------
        p070_parse_one_record(l_input_line);
  
        -----------------------------------------------------------------------------
        -- given the payment method, obtain the receipt method id
        -----------------------------------------------------------------------------   
        p080_get_receipt_method_id(v_payment_method, v_receipt_method_id);
      
        -----------------------------------------------------------------------------
        -- Given transaction number, extract the corresponding customer trx id
        -----------------------------------------------------------------------------
        p090_get_customer_trx_id(v_transaction_number, v_customer_trx_id);
  
        -----------------------------------------------------------------------------
        -- Reformat date columns from input file into date variable (DD-MON-RR format)
        -----------------------------------------------------------------------------
        p110_convert_all_dates;
      
        -----------------------------------------------------------------------------
        -- Set currency exchange fields to '' if currency is USD
        -----------------------------------------------------------------------------
        p115_set_usd_exchange_fields;

        -----------------------------------------------------------------------------
        -- if debugging is yes, display parsed out columns for current record
        -----------------------------------------------------------------------------
        p120_display_columns;
  
        -----------------------------------------------------------------------------
        -- populate the record fields that will be used to insert the attribute columns
        -----------------------------------------------------------------------------
        p130_populate_attributes(v_attribute_rec);    
  
        -----------------------------------------------------------------------------
        -- enable debugging and output to file
        -----------------------------------------------------------------------------
        p140_enable_debugging;
  
        -----------------------------------------------------------------------------
        -- call the "create_and_apply" procedure to apply receipt
        -- n.b. client has never used apply on account (create_apply_on_acc) (QA)
        -- if invoice number/transaction number is not null, then use create_and_apply
        -- if transaction number is null, then use create_apply_on_acc
        -----------------------------------------------------------------------------
        IF length(v_transaction_number) > 0 THEN
            ar_receipt_api_pub.create_and_apply(
                p_api_version => 1.0, 
                p_init_msg_list => fnd_api.g_true, 
                p_commit => fnd_api.g_false,
                p_validation_level => fnd_api.g_valid_level_full, x_return_status => l_return_status,
                x_msg_count => l_msg_count, 
                x_msg_data => l_msg_data, 
                p_currency_code => v_currency_code, 
                p_exchange_rate_type => v_rate_type, 
                p_exchange_rate => v_exchange_rate, 
                p_exchange_rate_date => v_exchange_rate_date, -- v_accounting_date2,
                p_amount => v_amount_applied, -- v_receipt_amount,
                p_receipt_number => v_receipt_number, 
                p_receipt_date => v_receipt_date2, 
                p_gl_date => v_accounting_date2,
                p_customer_number => v_customer_number, 
                p_receipt_method_id => v_receipt_method_id,
                p_attribute_rec => v_attribute_rec, 
                p_cr_id => l_cash_receipt_id, 
                p_customer_trx_id => v_customer_trx_id,
                p_amount_applied => v_amount_applied, 
                p_apply_date => v_apply_date2
            );
        ELSE
            ar_receipt_api_pub.create_apply_on_acc(
                p_api_version => 1.0, 
                p_init_msg_list => fnd_api.g_true, 
                p_commit => fnd_api.g_false, 
                p_validation_level => fnd_api.g_valid_level_full, 
                x_return_status => l_return_status,
                x_msg_count => l_msg_count, 
                x_msg_data => l_msg_data, 
                p_currency_code => v_currency_code, 
                p_exchange_rate_type => v_rate_type, 
                p_exchange_rate => v_exchange_rate, 
                p_exchange_rate_date => v_exchange_rate_date, -- v_accounting_date2,
                p_amount => v_amount_applied, -- v_receipt_amount,
                p_receipt_number => v_receipt_number, 
                p_receipt_date => v_receipt_date2, 
                p_gl_date => v_accounting_date2,
                p_customer_number => v_customer_number, p_receipt_method_id => v_receipt_method_id,
                p_attribute_rec => v_attribute_rec, 
                p_cr_id => l_cash_receipt_id,
                p_amount_applied => v_amount_applied,
                p_apply_date => v_apply_date2
            );
        END IF;
      
        -----------------------------------------------------------------------------
        -- print status information about ar_receipt_api_pub procedure call
        -----------------------------------------------------------------------------
        p150_print_status_info(l_return_status, l_msg_count, l_msg_data, l_cash_receipt_id, v_receipt_number, n_total_successful);
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

    -----------------------------------------------------------------------------
    -- turn off debugging, if the debug flag was set to yes
    -----------------------------------------------------------------------------
    p180_disable_debugging;
  
    -----------------------------------------------------------------------------
    -- delete the row from fnd_lookup_values (flv) for the filename parameter
    -----------------------------------------------------------------------------
    p190_delete_filename_from_flv(gv_datafile);
EXCEPTION
--  WHEN no_data_found THEN
--    dbms_output.put_line('ERROR OCCURRED: ' || n_total_rows);
--    dbms_output.put_line('ERROR OCCURRED: ' || n_total_rows);
    WHEN OTHERS THEN
        dbms_output.put_line('Exception occurred in main driver');
        dbms_output.put_line(sqlerrm);
END;
/

