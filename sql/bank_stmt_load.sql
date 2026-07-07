--------------------------------------------------------------------------------
-- bank_stmt_load.sql
--------------------------------------------------------------------------------
-- Custom script to load bank statement data from a CSV data file into EBS.
-- The CSV data file is read and data inserted into the CE Bank Statement
-- interface tables: CE_STATEMENT_HEADERS_INT and CE_STATEMENT_LINES_INTERFACE
-- 
-- Data is read from the ~/bankstmt.csv file on the database server and loaded 
-- into EBS. Note: you must cater for double-quote fields.
--------------------------------------------------------------------------------
-- Note that database directory permissions must be set up and granted before
-- the data file can be read. To grant permission, execute these steps:
-- CONNECT SYSTEM/MANAGER
-- CREATE DIRECTORY AR_DATA_DIR AS '/home/oracle';
-- GRANT READ ON DIRECTORY AR_DATA_DIR TO public;
--------------------------------------------------------------------------------
-- This script is placed on the application node in the $CE_TOP/sql directory:
-- For example: /u01/oracle/PROD/fs1/EBSapps/ce/12.2.0/sql
--
-- The data file bankstmt.csv should be placed on database mode in the ~/ directory:
-- /home/oracle
--------------------------------------------------------------------------------
-- Reference:
-- https://docs.oracle.com/cd/E26401_01/doc.122/e48842/T373258T376579.htm 
-- https://erpschools.com/erps/interface/interfaces-and-conversions 
-- 
-- 25-APR-2024  vseeram  Created
-- 08-MAY-2024  vseeram  Swap opening balance and closing balance values
--                       The lines are sorted in reverse chronological order.
--                       Oldest at bottom, newest at top.
--------------------------------------------------------------------------------


SET TRIMSPOOL ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE 1000000



DECLARE
    -----------------------------------------------------------------------------
    -- global constants
    -----------------------------------------------------------------------------
    c_delimiter                         CONSTANT VARCHAR2(1)  := ','; -- delimiter between fields in CSV file
    c_quote                             CONSTANT VARCHAR2(1)  := '"';
    c_yes                               CONSTANT VARCHAR2(1)  := 'Y';
    c_separator                         CONSTANT VARCHAR2(80) := '+' || LPad('+', 79, '-');
    c_operating_unit_name               CONSTANT VARCHAR2(80) := 'XX Operating Unit';
 
    ----------------------------------------------------------------------------
    -- The bank statement data file contains rows that start with the following:
    -- 1. Account Name
    -- 2. Pending Transactions
    -- 3. Date
    -- 4. No Data
    -- 5. Posted Transactions
    -- 6. Specified period
    -- 7. Date
    -- Lines 2, 3, 4, 5 and 7 can be ignored completely.
    -- In line 1, the account name must be captured.
    -- In line 6, the start and end dates must be captured
    --
    -- From line 8 onwards, data is stored in the following six columns:
    -- Date, Instrument #, Description, Debit Amount, Credit Amount, Running Balance
    -- Columns 1, 3, 4 and 5 must be stored (Date, Description, Debit Amount, Credit Amount)
    ----------------------------------------------------------------------------


    ----------------------------------------------------------------------------
    -- custom type for data read from input file
    ----------------------------------------------------------------------------
    TYPE InputRecTyp IS RECORD
    (
        token                           VARCHAR2(2000),
        account_name                    VARCHAR2(2000),
        start_date                      VARCHAR2(2000),
        end_date                        VARCHAR2(2000),
        trans_date                      VARCHAR2(2000),
        instrument_num                  VARCHAR2(2000),
        description                     VARCHAR2(2000),
        debit_amt                       VARCHAR2(2000),
        credit_amt                      VARCHAR2(2000),
        running_balance                 VARCHAR2(2000),        
        dr_code                         NUMBER,
        cr_code                         NUMBER
    );


    ----------------------------------------------------------------------------
    -- global variables to store values read from input file, bank statement
    -- header and bank statement lines
    ----------------------------------------------------------------------------
    gv_input_rec                        InputRecTyp;
    gv_bank_header                      ce_statement_headers_int%rowtype;
    gv_bank_line                        ce_statement_lines_interface%rowtype;


    ----------------------------------------------------------------------------
    -- global parameters passed from the concurrent program
    ----------------------------------------------------------------------------
    gp_commit                           VARCHAR2(255) := NVL('&1', 'N');
    gp_filename                         VARCHAR2(255) := NVL('&2', 'bankstmt.csv');  -- default data file
    gp_data_dir                         VARCHAR2(255) := NVL('&3', 'AR_DATA_DIR'); -- /home/oracle on db node
    gp_debug_flag                       VARCHAR2(255) := NVL(Upper('&4'), 'N');


    -----------------------------------------------------------------------------
    -- global variables: file handle, input line, num rows
    -----------------------------------------------------------------------------
    gb_debug_flag                       BOOLEAN := FALSE;
    gb_is_data_line                     BOOLEAN := FALSE;  -- does this input line have data?
    f_input_file                        utl_file.file_type;
    gv_input_line                       VARCHAR2(2000)      := '';
    gn_total_rows                       NUMBER := 0;  -- total number of rows in datafile
    gb_no_data_found                    BOOLEAN := FALSE;
    
    ge_invalid_file_operation           EXCEPTION;
    PRAGMA EXCEPTION_INIT(ge_invalid_file_operation, -29283);


    ----------------------------------------------------------------------------
    -- prints the first 255 characters in a string. To avoid the error:
    -- ORA-06502: PL/SQL: numeric or value error: host bind array too small
    ----------------------------------------------------------------------------
    PROCEDURE printout(p_line IN VARCHAR2) IS 
    BEGIN
        dbms_output.put_line(Substr(p_line, 1, 255));
    END printout;
    
    
    ----------------------------------------------------------------------------
    -- isnumeric - return true if parameter is a number
    ----------------------------------------------------------------------------
    FUNCTION isnumeric (p_number IN VARCHAR2) RETURN BOOLEAN IS
        lv_new_num                      NUMBER;
    BEGIN
        lv_new_num := to_number(p_number);
        RETURN TRUE;
    EXCEPTION
        WHEN value_error THEN
            RETURN FALSE;
        WHEN OTHERS THEN
            printout('Error occurred in isnumeric:');
            printout(SQLCODE || ': ' || SQLERRM);
    END isnumeric;

    
    ----------------------------------------------------------------------------
    -- isdate - return true if parameter is a date in the dd/mm/yyyy format
    ----------------------------------------------------------------------------
    FUNCTION isdate(p_date IN VARCHAR2) RETURN BOOLEAN IS
        lv_new_date                     DATE;
    BEGIN
        lv_new_date := To_Date(p_date, 'dd/mm/yyyy');
        RETURN TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END isdate;


    ----------------------------------------------------------------------------
    -- print a line if the debug flag is set to true
    ----------------------------------------------------------------------------
    PROCEDURE debug_print(p_line IN VARCHAR2) IS
    BEGIN
        IF gb_debug_flag THEN
            printout(p_line);
        END IF;
    EXCEPTION 
        WHEN OTHERS THEN
            printout('Error occurred in debug_print:');
            printout(SQLCODE || ': ' || SQLERRM);
    END debug_print;


    ----------------------------------------------------------------------------
    -- print a single token after parsing a comma-separated input line
    ----------------------------------------------------------------------------
    PROCEDURE p000_print_token(p_heading IN VARCHAR2, p_column IN OUT VARCHAR2, p_value IN VARCHAR2) IS
    BEGIN
        IF p_column IS NOT NULL THEN
            debug_print(RPad(p_heading || ' (' || p_column || ')', 35) || ': ''' || p_value || '''');
            p_column := CHR(ASCII(p_column) + 1);
        ELSE
            debug_print(RPad(p_heading, 35) || ': ''' || p_value || '''');
        END IF;
    EXCEPTION 
        WHEN OTHERS THEN
            printout('Error occurred in p000_print_token:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p000_print_token;
    

    -----------------------------------------------------------------------------
    -- print parameters passed to this program (usually via concurrent request)
    -----------------------------------------------------------------------------
    PROCEDURE p010_print_parameters IS
    BEGIN
        printout(c_separator);
        debug_print('gp_commit                 : ' || gp_commit);
        debug_print('gp_filename               : ' || gp_filename);
        debug_print('gp_debug_flag             : ' || gp_debug_flag);
        IF Upper(gp_debug_flag) = 'Y' THEN
            gb_debug_flag := TRUE;
        ELSE
            gb_debug_flag := FALSE;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p010_print_parameters:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p010_print_parameters;
    
    
    -----------------------------------------------------------------------------
    -- populate the static fields in the bank statement header record
    -----------------------------------------------------------------------------
    PROCEDURE p020_init_bank_stmt_header(p_bank_header IN OUT ce_statement_headers_int%rowtype) IS
    BEGIN
        p_bank_header.statement_date := SYSDATE;
        p_bank_header.control_begin_balance := NULL; -- needed to store initial value
        p_bank_header.control_total_dr := 0;
        p_bank_header.control_total_cr := 0;
        p_bank_header.control_end_balance := NULL;
        p_bank_header.control_dr_line_count := 0;
        p_bank_header.control_cr_line_count := 0;
        p_bank_header.control_line_count := 0;
        p_bank_header.created_by := 1;
        p_bank_header.creation_date := SYSDATE;
        p_bank_header.last_updated_by := 1;
        p_bank_header.last_update_date := SYSDATE;
        SELECT organization_id INTO p_bank_header.org_id FROM hr_operating_units WHERE name = c_operating_unit_name;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p020_init_bank_stmt_header:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p020_init_bank_stmt_header;
        
  
    -----------------------------------------------------------------------------
    -- read the next input line from the data file and clean up
    -----------------------------------------------------------------------------
    PROCEDURE p030_read_next_line(p_input_file IN OUT utl_file.file_type, p_total_rows_read IN OUT NUMBER, p_input_line OUT VARCHAR2, p_no_data_found OUT BOOLEAN) IS
    BEGIN
        p_no_data_found := FALSE;
        utl_file.get_line(p_input_file, p_input_line);
        p_input_line := Trim(REPLACE(REPLACE(p_input_line, CHR(10), ' '), CHR(13), ' ')); -- remove CRLF
        p_total_rows_read := p_total_rows_read + 1;
    EXCEPTION 
        WHEN no_data_found THEN 
            p_no_data_found := TRUE;
        WHEN OTHERS THEN
            printout('Error occurred in p030_read_next_line:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p030_read_next_line;


    -----------------------------------------------------------------------------
    -- print the line that was read from input file
    -----------------------------------------------------------------------------
    PROCEDURE p040_print_line(p_input_line IN VARCHAR2) IS
    BEGIN
        -- printout(c_separator);
        printout(p_input_line);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p040_print_line:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p040_print_line;
    

    -----------------------------------------------------------------------------
    -- given the input line, extract the next comma-separated token
    -- cater for double-quotes on line
    -----------------------------------------------------------------------------
    FUNCTION p050_get_next_token(p_input_line IN OUT VARCHAR2) RETURN VARCHAR2 IS
        lv_token                        VARCHAR2(255) := '';
        ln_quote                        NUMBER := 0;
    BEGIN
        -- check if the first character is a double quote
        IF Substr(p_input_line, 1, 1) = c_quote THEN
            ln_quote := Instr(p_input_line, c_quote, 2);
            IF ln_quote <= Length(p_input_line) THEN
                lv_token := Substr(p_input_line, 2, ln_quote - 2);
                p_input_line := Trim(Substr(p_input_line, ln_quote + 2));
            END IF;
      
        -- if not a double quote, check if the delimiter exists, then extract the next token up to the next delimiter
        ELSIF Instr(p_input_line, c_delimiter) > 0 THEN
            lv_token := Substr(p_input_line, 1, instr(p_input_line, c_delimiter) - 1);
            p_input_line := Trim(Substr(p_input_line, Instr(p_input_line, c_delimiter) + 1));

        -- if no delimiter remaining on line, use the line as the token
        ELSE
            lv_token := p_input_line;
            p_input_line := '';
        END IF;
        RETURN Trim(lv_token);
    EXCEPTION 
        WHEN OTHERS THEN
            printout('Error occurred in p050_get_next_token:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p050_get_next_token;


    -----------------------------------------------------------------------------
    -- check if the input line is valid, to determine if to parse into tokens
    -----------------------------------------------------------------------------
    FUNCTION p060_is_valid_line(p_input_line IN VARCHAR2) RETURN BOOLEAN IS
        lv_input_line                   VARCHAR2(2000) := p_input_line;
    BEGIN
        -- is the input line blank (length = 0)?
        IF Length(lv_input_line) = 0 THEN
            RETURN FALSE;
        END IF;
    
        -- does the input line have no columns (first character is a comma)?
        IF Substr(lv_input_line, 1, 1) = c_delimiter THEN
            RETURN FALSE;
        END IF;
    
        RETURN TRUE;
    EXCEPTION 
        WHEN no_data_found THEN 
            RETURN FALSE;
        WHEN OTHERS THEN
            printout('Error occurred in p060_is_valid_line:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p060_is_valid_line;


    -----------------------------------------------------------------------------
    -- given the end date for the specified period, return the statement number
    -----------------------------------------------------------------------------
    PROCEDURE p065_get_statement_number(p_statement_date IN VARCHAR2, p_bank_header IN OUT ce_statement_headers_int%rowtype) IS
        lv_statement_number             VARCHAR2(2000);
        ld_statement_date               DATE;
        lv_version                      VARCHAR2(10) := 'A';
    BEGIN
        ld_statement_date := To_Date(p_statement_date, 'dd/mm/yyyy');

        SELECT Max(statement_number)
        INTO lv_statement_number
        FROM ce_statement_headers_int
        WHERE statement_number LIKE '%' || To_Char(ld_statement_date, 'YYYYMMDD') || '%';
        
        IF lv_statement_number IS NOT NULL THEN
            IF Length(lv_statement_number) > 0 THEN
                lv_version := Substr(lv_statement_number, Length(lv_statement_number), 1);
                IF lv_version = 'Z' THEN
                    lv_version := '_A';
                ELSIF lv_version >= 'A' AND lv_version < 'Z' THEN
                    lv_version := Chr(Ascii(lv_version) + 1);
                ELSE
                    lv_version := 'A';
                END IF;
            END IF;
        END IF;
        p_bank_header.statement_number := 'XX_' || To_Char(ld_statement_date, 'YYYYMMDD') || lv_version;
    EXCEPTION 
        WHEN OTHERS THEN
            printout('Error occurred in p065_get_statement_number');
            printout(SQLCODE || ': ' || SQLERRM);
    END p065_get_statement_number;


    -----------------------------------------------------------------------------
    -- parse input line and store in variables
    -----------------------------------------------------------------------------
    PROCEDURE p070_parse_input_line(p_input_line IN VARCHAR2, p_input_rec IN OUT InputRecTyp, p_bank_header IN OUT ce_statement_headers_int%rowtype) IS
        lv_input_line                   VARCHAR2(2000) := p_input_line;
        lv_token                        VARCHAR2(2000) := NULL;
        ln_bank_account_id              apps.ce_bank_accounts.bank_account_id%type;
        ln_bank_id                      apps.hz_parties.party_id%type;
        ln_bank_branch_id               apps.hz_parties.party_id%type;
        ln_first_dash                   NUMBER;
        ln_second_dash                  NUMBER;
    BEGIN
        lv_token                        := '';
        lv_token                        := p050_get_next_token(lv_input_line);
        p_input_rec.token               := lv_token;
        IF lv_token = 'Account Name' THEN
            p_input_rec.account_name    := p050_get_next_token(lv_input_line);

            -- extract the currency code
            IF p_bank_header.currency_code IS NULL THEN
                ln_second_dash := Instr(p_input_rec.account_name, '-', -1);
                p_bank_header.currency_code := SubStr(p_input_rec.account_name, ln_second_dash + 1, 3);
            END IF;

            -- extract the bank account number
            -- bank account number needed for bank stmt lines
            IF p_bank_header.bank_account_num IS NULL THEN
                ln_first_dash := Instr(p_input_rec.account_name, '-');
                ln_second_dash := Instr(p_input_rec.account_name, '-', -1);
                p_bank_header.bank_account_num := SubStr(p_input_rec.account_name, ln_first_dash + 1, ln_second_dash - ln_first_dash - 1);
                printout(p_bank_header.bank_account_num);
            END IF;

            -- get bank account ID for the bank account number
            SELECT bank_account_id, bank_id, bank_branch_id 
            INTO ln_bank_account_id, ln_bank_id, ln_bank_branch_id 
            FROM apps.ce_bank_accounts ceba 
            WHERE bank_account_num = p_bank_header.bank_account_num;

            -- get transaction code for debit transactions
            SELECT trx_code INTO p_input_rec.dr_code FROM ce_transaction_codes WHERE 
            bank_account_id = ln_bank_account_id AND trx_type = 'DEBIT';

            -- get transaction code for credit transactions
            SELECT trx_code INTO p_input_rec.cr_code FROM ce_transaction_codes WHERE 
            bank_account_id = ln_bank_account_id AND trx_type = 'CREDIT';

            -- get the bank name 
            SELECT party_name
            INTO p_bank_header.bank_name
            FROM apps.hz_parties
            WHERE party_id = ln_bank_id
            AND party_type = 'ORGANIZATION';
            
            -- get the bank branch
            SELECT party_name
            INTO p_bank_header.bank_branch_name
            FROM apps.hz_parties
            WHERE party_id = ln_bank_branch_id
            AND party_type = 'ORGANIZATION';
            
        ELSIF lv_token = 'Specified period' THEN
            p_input_rec.start_date      := p050_get_next_token(lv_input_line);
            p_input_rec.end_date        := p050_get_next_token(lv_input_line);
            p065_get_statement_number(p_input_rec.end_date, p_bank_header);
        ELSIF isdate(lv_token) THEN
            gb_is_data_line             := TRUE;
            p_input_rec.trans_date      := lv_token;
            p_input_rec.instrument_num  := p050_get_next_token(lv_input_line);
            p_input_rec.description     := p050_get_next_token(lv_input_line);
            p_input_rec.debit_amt       := p050_get_next_token(lv_input_line);
            p_input_rec.credit_amt      := p050_get_next_token(lv_input_line);
            p_input_rec.running_balance := p050_get_next_token(lv_input_line);
        END IF;        
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p070_parse_input_line:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p070_parse_input_line;


    -----------------------------------------------------------------------------
    -- print parsed tokens from input line/p_input_rec (useful when debugging)
    -- ID columns that were looked up  are also printed
    -----------------------------------------------------------------------------
    PROCEDURE p080_print_input_fields(p_input_rec IN OUT InputRecTyp) IS
        lv_column                       VARCHAR2(1) := '';
    BEGIN
        printout(c_separator);
        p000_print_token('TOKEN', lv_column, p_input_rec.token);
        p000_print_token('ACCOUNT NAME', lv_column, p_input_rec.account_name);
        p000_print_token('START DATE', lv_column, p_input_rec.start_date);
        p000_print_token('END DATE', lv_column, p_input_rec.end_date);
        p000_print_token('DATE', lv_column, p_input_rec.trans_date);
        p000_print_token('INSTRUMENT', lv_column, p_input_rec.instrument_num);
        p000_print_token('DESCRIPTION', lv_column, p_input_rec.description);
        p000_print_token('DEBIT AMT', lv_column, p_input_rec.debit_amt);
        p000_print_token('CREDIT AMT', lv_column, p_input_rec.credit_amt);
        p000_print_token('BALANCE', lv_column, p_input_rec.running_balance);
        p000_print_token('DR_CODE', lv_column, p_input_rec.dr_code);
        p000_print_token('CR_CODE', lv_column, p_input_rec.cr_code);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p080_print_input_fields:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p080_print_input_fields;

    
    -----------------------------------------------------------------------------
    -- process each input line by updating the bank statement header record
    -- if either the debit amt or credit amt is '-', assume that the other field
    -- is numeric
    -----------------------------------------------------------------------------
    PROCEDURE p085_get_currency_amount(p_input_amt IN VARCHAR2, p_output_amt OUT NUMBER) IS
        lv_input_amt                    VARCHAR2(2000);    
    BEGIN
        -- if p_input_amt is numeric, convert to number and exit
        IF isnumeric(p_input_amt) THEN
            p_output_amt := To_Number(p_input_amt);
            RETURN;
        END IF;
        
        -- if p_input_amt has commas, remove them, then convert to number and exit
        lv_input_amt := Replace(p_input_amt, ',', '');
        IF isnumeric(lv_input_amt) THEN
            p_output_amt := To_Number(lv_input_amt);
            RETURN;
        END IF;
        
        IF Substr(lv_input_amt, 1, 1) = '(' THEN
            lv_input_amt := '-' || Replace(Replace(lv_input_amt, '(', ''), ')', '');
            IF isnumeric(lv_input_amt) THEN
                p_output_amt := To_Number(lv_input_amt);
                RETURN;
            END IF;
        END IF;
        
        printout('Invalid number p_input_amt: ' || p_input_amt);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p085_get_currency_amount:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p085_get_currency_amount;


    -----------------------------------------------------------------------------
    -- process each input line by updating the bank statement header record
    -- if either the debit amt or credit amt is '-', assume that the other field
    -- is numeric
    -----------------------------------------------------------------------------
    PROCEDURE p090_process_line(p_input_rec IN InputRecTyp, 
        p_bank_header IN OUT ce_statement_headers_int%rowtype,
        p_bank_line IN OUT ce_statement_lines_interface%rowtype) IS
        lv_debit_amt                    VARCHAR2(255) := '';
        ln_amount                       NUMBER := 0;
        ln_balance                      NUMBER := 0;
    BEGIN
        -- update the bank header's control totals closing balance, 
        -- (which is the first running balance in the data file)
        p085_get_currency_amount(p_input_rec.running_balance, ln_balance);
        -- ln_balance := To_Number(p_input_rec.running_balance, '999,999,999,999.99');
        IF p_bank_header.control_end_balance IS NULL THEN
            p_bank_header.control_end_balance := ln_balance;
        END IF;

        -- update the bank header control totals: 
        -- control_cr_line_count, control_dr_line_count, control_total_cr, control_total_dr, control_line_count
        IF p_input_rec.debit_amt IN ('-', '0') THEN 
            p085_get_currency_amount(p_input_rec.credit_amt, ln_amount);
            p_bank_header.control_total_cr := p_bank_header.control_total_cr + Abs(ln_amount);
            p_bank_header.control_cr_line_count := p_bank_header.control_cr_line_count + 1;
            p_bank_header.control_line_count := p_bank_header.control_line_count + 1;
            p_bank_line.trx_code := p_input_rec.cr_code;
        ELSIF p_input_rec.credit_amt IN ('-', '0') THEN 
            p085_get_currency_amount(p_input_rec.debit_amt, ln_amount);
            p_bank_header.control_total_dr := p_bank_header.control_total_dr + Abs(ln_amount); 
            p_bank_header.control_dr_line_count := p_bank_header.control_dr_line_count + 1;
            p_bank_header.control_line_count := p_bank_header.control_line_count + 1;
            p_bank_line.trx_code := p_input_rec.dr_code;
        ELSE
            printout('Error occurred in p090_process_line:');
            printout('gv_debit_amt  : ' || p_input_rec.debit_amt);
            printout('gv_credit_amt : ' || p_input_rec.credit_amt);
            printout('gv_debit_amt  : ' || To_Number(p_input_rec.debit_amt, '(999,999,999,999.99)'));
            printout('gv_credit_amt : ' || To_Number(p_input_rec.credit_amt, '999,999,999,999.99'));
        END IF;

        p_bank_line.bank_account_num := p_bank_header.bank_account_num;
        p_bank_line.statement_number := p_bank_header.statement_number;
        p_bank_line.line_number := p_bank_header.control_line_count;
        p_bank_line.trx_date := To_Date(p_input_rec.trans_date, 'dd/mm/yyyy');
        p_bank_line.trx_text := p_input_rec.description;
        p_bank_line.amount := Abs(ln_amount);
        p_bank_line.effective_date := To_Date(p_input_rec.trans_date, 'dd/mm/yyyy');
        p_bank_line.currency_code := p_bank_header.currency_code;
        p_bank_line.bank_acct_currency_code := p_bank_header.currency_code;
        p_bank_line.created_by := p_bank_header.created_by;
        p_bank_line.creation_date := p_bank_header.creation_date;
        p_bank_line.last_updated_by := p_bank_header.last_updated_by;
        p_bank_line.last_update_date := p_bank_header.last_update_date;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p090_process_line:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p090_process_line;
    

    -----------------------------------------------------------------------------
    -- prints the fields to insert into the bank statement lines table
    -----------------------------------------------------------------------------
    PROCEDURE p095_print_bank_stmt_lines(p_bank_line IN ce_statement_lines_interface%rowtype) IS
        lv_column                       VARCHAR2(1) := '';
    BEGIN
        printout(c_separator);
        p000_print_token('bank_account_num', lv_column, p_bank_line.bank_account_num);
        p000_print_token('statement_number', lv_column, p_bank_line.statement_number);
        p000_print_token('line_number', lv_column, p_bank_line.line_number);
        p000_print_token('trx_date', lv_column, p_bank_line.trx_date);
        p000_print_token('trx_code', lv_column, p_bank_line.trx_code);
        p000_print_token('trx_text', lv_column, p_bank_line.trx_text);
        p000_print_token('amount', lv_column, p_bank_line.amount);
        p000_print_token('currency_code', lv_column, p_bank_line.currency_code);
        p000_print_token('created_by', lv_column, p_bank_line.created_by);
        p000_print_token('creation_date', lv_column, p_bank_line.creation_date);
        p000_print_token('last_updated_by', lv_column, p_bank_line.last_updated_by);
        p000_print_token('last_update_date', lv_column, p_bank_line.last_update_date);
        p000_print_token('bank_acct_currency_code', lv_column, p_bank_line.bank_acct_currency_code);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p095_print_bank_stmt_lines:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p095_print_bank_stmt_lines;


    -----------------------------------------------------------------------------
    -- insert data into CE_STATEMENT_LINES_INTERFACE table
    -----------------------------------------------------------------------------
    PROCEDURE p100_insert_bank_stmt_lines(p_bank_line IN ce_statement_lines_interface%rowtype) IS
    BEGIN
        -- p095_print_bank_stmt_lines(p_bank_line);
        INSERT INTO ce_statement_lines_interface (
            bank_account_num,
            statement_number,
            line_number,
            trx_date,
            trx_code,
            trx_text,
            amount,
            currency_code,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            bank_acct_currency_code
        )
        VALUES (
            p_bank_line.bank_account_num,
            p_bank_line.statement_number,
            p_bank_line.line_number,
            p_bank_line.trx_date,
            p_bank_line.trx_code,
            p_bank_line.trx_text,
            p_bank_line.amount,
            p_bank_line.currency_code,
            p_bank_line.created_by,
            p_bank_line.creation_date,
            p_bank_line.last_updated_by,
            p_bank_line.last_update_date,
            p_bank_line.bank_acct_currency_code
        );
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p100_insert_bank_stmt_lines:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p100_insert_bank_stmt_lines;


    -----------------------------------------------------------------------------
    -- after all rows read, make final updates to bank header record before inserting
    -----------------------------------------------------------------------------
    PROCEDURE p110_post_process_bank_stmt_header(p_bank_header IN OUT CE_STATEMENT_HEADERS_INT%ROWTYPE) IS
        ln_first_dash                   NUMBER;
        ln_second_dash                  NUMBER;
        ln_balance                      NUMBER;
    BEGIN
        -- update the control opening balance on the bank statement header
        p_bank_header.control_begin_balance := p_bank_header.control_end_balance + p_bank_header.control_total_dr - p_bank_header.control_total_cr;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p110_post_process_bank_stmt_header:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p110_post_process_bank_stmt_header;


    -----------------------------------------------------------------------------
    -- insert single row into ce_statement_headers_int table
    -----------------------------------------------------------------------------
    PROCEDURE p120_insert_bank_stmt_header(p_bank_header IN CE_STATEMENT_HEADERS_INT%ROWTYPE) IS
    BEGIN
        INSERT INTO ce_statement_headers_int (
            statement_number,
            bank_account_num,
            statement_date,
            bank_name,
            bank_branch_name,
            control_begin_balance,
            control_total_dr,
            control_total_cr,
            control_end_balance,
            control_dr_line_count,
            control_cr_line_count,
            control_line_count,
            record_status_flag,
            currency_code,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            org_id
        ) 
        VALUES (
            p_bank_header.statement_number,
            p_bank_header.bank_account_num,
            p_bank_header.statement_date,
            p_bank_header.bank_name,
            p_bank_header.bank_branch_name,
            p_bank_header.control_begin_balance,
            p_bank_header.control_total_dr,
            p_bank_header.control_total_cr,
            p_bank_header.control_end_balance,
            p_bank_header.control_dr_line_count,
            p_bank_header.control_cr_line_count,
            p_bank_header.control_line_count,
            p_bank_header.record_status_flag,
            p_bank_header.currency_code,
            p_bank_header.created_by,
            p_bank_header.creation_date,
            p_bank_header.last_updated_by,
            p_bank_header.last_update_date,
            p_bank_header.org_id
        );
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p120_insert_bank_stmt_header:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p120_insert_bank_stmt_header;
    
    
    -----------------------------------------------------------------------------
    -- commit or rollback INSERT statements?
    -----------------------------------------------------------------------------
    PROCEDURE p130_commit_rollback(p_commit IN VARCHAR2) IS
    BEGIN
        dbms_output.put('Commit flag is set to ' || p_commit || ', ');
        IF p_commit = c_yes THEN
            printout('committing transactions...');
            COMMIT;
        ELSE
            printout('rolling back transactions...');
            ROLLBACK;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p130_commit_rollback:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p130_commit_rollback;


    ----------------------------------------------------------------------------
    -- print summary from load
    ----------------------------------------------------------------------------
    PROCEDURE p140_print_summary(p_total_rows_read IN NUMBER) IS
    BEGIN
        printout(c_separator);
        printout('Total Rows Read     : ' || Lpad(p_total_rows_read, 4));
        printout(Rpad('----- Data file closed ', 80, '-'));
        printout(Rpad('----- Load script is completed ', 80, '-'));
        printout(c_separator);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p140_print_summary:');
            printout(SQLCODE || ': ' || SQLERRM);
    END p140_print_summary;


--------------------------------------------------------------------------------
-- main driver
--------------------------------------------------------------------------------
BEGIN
    p010_print_parameters;
    
    f_input_file := utl_file.fopen('AR_DATA_DIR', gp_filename, 'r');
    printout(Rpad('----- Data file ' || gp_filename || ' opened ', 80, '-'));

    p020_init_bank_stmt_header(gv_bank_header);
    LOOP
        p030_read_next_line(f_input_file, gn_total_rows, gv_input_line, gb_no_data_found);
    
        IF gb_no_data_found THEN
            EXIT;
        END IF;

        p040_print_line(gv_input_line);

        p070_parse_input_line(gv_input_line, gv_input_rec, gv_bank_header);

        p080_print_input_fields(gv_input_rec);

        IF gb_is_data_line THEN
            p090_process_line(gv_input_rec, gv_bank_header, gv_bank_line);
            p100_insert_bank_stmt_lines(gv_bank_line);
        END IF;
    END LOOP;
    p110_post_process_bank_stmt_header(gv_bank_header);
    
    p120_insert_bank_stmt_header(gv_bank_header);
    
    p130_commit_rollback(gp_commit);
    utl_file.fclose(f_input_file);
    
    p140_print_summary(gn_total_rows);
    EXCEPTION
        WHEN ge_invalid_file_operation THEN
            printout('Invalid file operation: file not found?');
            printout(SQLCODE || ': ' || SQLERRM);
        WHEN OTHERS THEN
            printout(SQLCODE || ': ' || SQLERRM);
    END;
/

SHOW ERRORS
