--------------------------------------------------------------------------------
-- xx_om_sales.sql
--------------------------------------------------------------------------------
-- Custom script to load sales orders from a CSV data file into XX EBS.
-- The CSV data file is read, insert the data into the Order Management 
-- interface tables: OE_HEADERS_IFACE_ALL and OE_LINES_IFACE_ALL.
-- 
-- Data is read from the ~/orders.csv file and loaded into EBS. Must cater for
-- double-quote fields.
--
-- Note that database directory permissions must be set up and granted before
-- the data file can be read. To grant permission, execute these steps:
-- CONNECT SYSTEM/MANAGER
-- CREATE DIRECTORY AR_DATA_DIR AS '/home/oracle';
-- GRANT READ ON DIRECTORY AR_DATA_DIR TO public;
--
-- This script is placed on the application node in the $OM_TOP/sql directory:
-- /u00/app/oracle/prodappl/om/12.2.0/sql
-- The data file orders.csv should be placed on database mode in the ~/ directory:
-- /home/oracle
--
-- Reference:
-- https://docs.oracle.com/cd/E26401_01/doc.122/e48842/T373258T376579.htm 
-- https://erpschools.com/erps/interface/interfaces-and-conversions 
-- 
-- 07-NOV-2022  vseeram  Created
-- 24-JAN-2023  vseeram  Added lookup procedures for the org_ids.
-- 31-JAN-2023  vseeram  Added order_number to oe_headers_iface_all (p100_insert_tbl)
-- 31-JAN-2023  vseeram  Updated procedure p076_lookup_inventory_item_id
-- 02-FEB-2023  vseeram  Added line_number, hz_account_num_s sequence
-- 07-FEB-2023  vseeram  Added code to use the same orig_sys_document_ref for multiple lines
-- 08-FEB-2023  vseeram  Added p095_chk_insert_header_flag to check if to insert header
-- 25-MAY-2023  vseeram  Change hardcoded values for UAT3 (price list and order type id)
-- 09-FEB-2023  vseeram  Fixed some bugs in p100_insert_tbl (both INSERT statements)
--------------------------------------------------------------------------------


SET TRIMSPOOL ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE 1000000
-- EXEC dbms_application_info.set_client_info('82'); -- used in 11i, not R12

DECLARE
    -----------------------------------------------------------------------------
    -- global constants
    -----------------------------------------------------------------------------
    c_delimiter              CONSTANT VARCHAR2(1) := ',';
    c_quote                  CONSTANT VARCHAR2(1) := '"';
    c_yes                    CONSTANT VARCHAR2(1) := 'Y';
    c_heading                CONSTANT VARCHAR2(6) := 'SUB NO'; -- first column heading
    c_curr_date              CONSTANT DATE := trunc(sysdate);
    c_separator              CONSTANT VARCHAR2(80) := '+' || lpad('+', 79, '-');
    c_operating_unit_name    CONSTANT VARCHAR2(80) := 'XX Operating Unit';
  
    -- File layout of the lines in the data file:
    -- CUSTOMER_NUMBER, ORDERED_DATE, SALESREP_ID, SOLD_TO_ORG_ID, INVOICE_TO_ORG_ID, SHIP_TO_ORG_ID, INVENTORY_ITEM_ID, ORDERED_QUANTITY
    
    -- Mapping layout in specification document:
    -- CUSTOMER_NUMBER, ORDERED_DATE, ORDER_NUMBER, SALESREP_ID, LINE_NUMBER, INVENTORY_ITEM_ID, ORDERED_QUANTITY
    
    
    -----------------------------------------------------------------------------
    -- global parameters from concurrent program
    -----------------------------------------------------------------------------
    gp_commit                VARCHAR2(255) := nvl('&1', 'N');
    gp_filename              VARCHAR2(255) := nvl('&2', 'orders.csv');  -- default data file  
    gp_data_dir              VARCHAR2(255) := nvl('&3', 'AR_DATA_DIR'); -- /home/oracle on db node
    gp_debug                 VARCHAR2(255) := nvl(upper('&4'), 'N');


    -----------------------------------------------------------------------------
    -- global variables to store values read from input file
    -----------------------------------------------------------------------------
    gv_customer_number       VARCHAR2(2000);
    gv_ordered_date          VARCHAR2(2000);
    gv_order_number          VARCHAR2(2000);
    gv_salesrep              VARCHAR2(2000);
    gv_line_number           VARCHAR2(2000);
    gv_sold_to_org           VARCHAR2(2000);
    gv_invoice_to_org        VARCHAR2(2000);
    gv_ship_to_org           VARCHAR2(2000);
    gv_inventory_item        VARCHAR2(2000);
    gv_ordered_quantity      VARCHAR2(2000); -- NUMBER;

  
    -----------------------------------------------------------------------------
    -- global variables - need to query the following ID numbers
    -----------------------------------------------------------------------------
    gn_salesrep_id           NUMBER;
    gv_orig_system_reference VARCHAR2(2000);
    gn_sold_to_org_id        NUMBER;
    gn_invoice_to_org_id     NUMBER;
    gn_ship_to_org_id        NUMBER;
    gn_order_source_id       NUMBER;
    gn_inventory_item_id     NUMBER;
    gb_debug_flag            BOOLEAN := FALSE;
    gn_orig_system_reference NUMBER := 0;
--  gn_prev_system_reference    NUMBER              := 0;
    gv_prev_system_reference VARCHAR2(2000) := '';
    gv_price_list            VARCHAR2(2000);
    gv_order_type_id         NUMBER;
    gv_prev_customer_number  VARCHAR2(2000) := ' ';
    gv_prev_ordered_date     VARCHAR2(2000) := ' ';
    gv_prev_order_number     VARCHAR2(2000) := ' ';
    gv_prev_salesrep         VARCHAR2(2000) := ' ';
    gb_insert_header_flag    BOOLEAN;


    -----------------------------------------------------------------------------
    -- remaining local variables: file handle, input line, num rows
    -----------------------------------------------------------------------------
    input_file               utl_file.file_type;
    lv_input_line            VARCHAR2(2000) := '';
    ln_total_rows            NUMBER := 0;
--  ln_success                  NUMBER := 0;
--  ln_failure                  NUMBER := 0;
--  ln_rejected                 NUMBER := 0;
    l_return_status          VARCHAR2(1);
    lb_no_data_found         BOOLEAN := FALSE;
    lv_org_id                NUMBER := 0; -- 82; -- VARCHAR2(255) := '101';

    le_invalid_file EXCEPTION;
    PRAGMA exception_init ( le_invalid_file, -29283 );


    -----------------------------------------------------------------------------
    -- prints the first 255 characters in a string. To avoid the error:
    -- ORA-06502: PL/SQL: numeric or value error: host bind array too small
    -----------------------------------------------------------------------------
    PROCEDURE printout (
        p_line IN VARCHAR2
    ) IS
    BEGIN
        dbms_output.put_line(substr(p_line, 1, 255));
    END printout;


    -----------------------------------------------------------------------------
    -- isnumeric - return true if parameter is a number
    -----------------------------------------------------------------------------
    FUNCTION isnumeric (
        p_number IN VARCHAR2
    ) RETURN BOOLEAN IS
        lv_new_num NUMBER;
    BEGIN
        lv_new_num := TO_NUMBER ( p_number );
        RETURN TRUE;
    EXCEPTION
        WHEN value_error THEN
            RETURN FALSE;
    END isnumeric;


    -----------------------------------------------------------------------------
    -- print a line if the debug flag is set to true
    -----------------------------------------------------------------------------
    PROCEDURE debug_print (
        p_line IN VARCHAR2
    ) IS
    BEGIN
        IF gb_debug_flag THEN
            printout(p_line);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in debug_print:');
            printout(sqlcode || ': ' || sqlerrm);
    END debug_print;


    -----------------------------------------------------------------------------
    -- print a single token after parsing a comma-separated input line
    -----------------------------------------------------------------------------
    PROCEDURE p000_print_token (
        p_heading IN VARCHAR2,
        p_column  IN OUT VARCHAR2,
        p_value   IN VARCHAR2
    ) IS
    BEGIN
        IF p_column IS NOT NULL THEN
            debug_print(rpad(p_heading || ' (' || p_column || ')', 35) || ': ''' || p_value || '''');
            p_column := chr(ascii(p_column) + 1);
        ELSE
            debug_print(rpad(p_heading, 35) || ': ''' || p_value || '''');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p000_print_token:');
            printout(sqlcode || ': ' || sqlerrm);
    END p000_print_token;


    -----------------------------------------------------------------------------
    -- print parameters passed to this program (usually via concurrent request)
    -----------------------------------------------------------------------------
    PROCEDURE p010_print_parameters IS
    BEGIN
        printout(c_separator);
        debug_print('gp_commit                 : ' || gp_commit);
        debug_print('gp_filename               : ' || gp_filename);
        debug_print('gp_debug                  : ' || gp_debug);
        IF upper(gp_debug) = 'Y' THEN
            gb_debug_flag := TRUE;
        ELSE
            gb_debug_flag := FALSE;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p010_print_parameters:');
            printout(sqlcode || ': ' || sqlerrm);
    END p010_print_parameters;


    -----------------------------------------------------------------------------
    -- delete all rows from oe_headers_iface_all and oe_lines_iface_all tables
    -- n.b. not committed; will be commited or rolled back depending on gp_commit
    -----------------------------------------------------------------------------
    PROCEDURE p015_delete_tbl IS
    BEGIN
        DELETE FROM oe_headers_iface_all;

        DELETE FROM oe_lines_iface_all;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p015_delete_tbl:');
            printout(sqlcode || ': ' || sqlerrm);
    END p015_delete_tbl;
  
  
    -----------------------------------------------------------------------------
    -- read the next input line from the data file and clean up
    -- 07-NOV-2022 VS: Remove CRLF from end of input line
    -----------------------------------------------------------------------------
    PROCEDURE p020_read_next_line (
        p_input_file      IN OUT utl_file.file_type,
        p_total_rows_read IN OUT NUMBER,
        p_input_line      OUT VARCHAR2,
        p_no_data_found   OUT BOOLEAN
    ) IS
    BEGIN
        p_no_data_found := FALSE;
        utl_file.get_line(p_input_file, p_input_line);
        p_input_line := replace(replace(p_input_line, chr(10), ' '), chr(13), ' '); -- remove CRLF
        p_input_line := trim(p_input_line);
        p_total_rows_read := p_total_rows_read + 1;
    EXCEPTION
        WHEN no_data_found THEN
            p_no_data_found := TRUE;
        WHEN OTHERS THEN
            printout('Error occurred in p020_read_next_line:');
            printout(sqlcode || ': ' || sqlerrm);
    END p020_read_next_line;


    -----------------------------------------------------------------------------
    -- print the line that was read from input file
    -----------------------------------------------------------------------------
    PROCEDURE p030_print_line (
        p_input_line IN VARCHAR2
    ) IS
    BEGIN
        printout(c_separator);
        printout(p_input_line);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p030_print_line:');
            printout(sqlcode || ': ' || sqlerrm);
    END p030_print_line;


    -----------------------------------------------------------------------------
    -- given the input line, extract the next comma-separated token
    -- cater for double-quotes on line
    -- 07-NOV-2022 VS: Cater for no delimiter at end of line
    -----------------------------------------------------------------------------
    FUNCTION p040_get_next_token (
        p_input_line IN OUT VARCHAR2
    ) RETURN VARCHAR2 IS
        lv_token VARCHAR2(255) := '';
        ln_quote NUMBER := 0;
    BEGIN
        -- check if the first character is a double quote
        IF substr(p_input_line, 1, 1) = c_quote THEN
            ln_quote := instr(p_input_line, c_quote, 2);
            IF ln_quote <= length(p_input_line) THEN
                lv_token := substr(p_input_line, 2, ln_quote - 2);
                p_input_line := trim(substr(p_input_line, ln_quote + 2));
            END IF;
      
        -- if not a double quote, check if the delimiter exists, then extract the next token up to the next delimiter
        ELSIF instr(p_input_line, c_delimiter) > 0 THEN
            lv_token := substr(p_input_line, 1, instr(p_input_line, c_delimiter) - 1);

            p_input_line := trim(substr(p_input_line, instr(p_input_line, c_delimiter) + 1));
        -- if no delimiter remaining on line, use the line as the token
        ELSE
            lv_token := p_input_line;
            p_input_line := '';
        END IF;

        RETURN trim(lv_token);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p040_get_next_token:');
            printout(sqlcode || ': ' || sqlerrm);
    END p040_get_next_token;


    -----------------------------------------------------------------------------
    -- validate the input line, to determine if to parse into tokens
    -----------------------------------------------------------------------------
    FUNCTION p050_is_valid_line (
        p_input_line IN VARCHAR2
    ) RETURN BOOLEAN IS
        lv_input_line VARCHAR2(2000) := p_input_line;
    BEGIN
        /* is the input line blank (length = 0)? */
        IF length(lv_input_line) = 0 THEN
            RETURN FALSE;
        END IF;
    
        /* does the input line have no columns (first character is a comma)? */
        IF substr(lv_input_line, 1, 1) = c_delimiter THEN
            RETURN FALSE;
        END IF;
    
        /* does the input line begin with 'SUB NO' (header row)? */
        IF p040_get_next_token(lv_input_line) = c_heading THEN
            RETURN FALSE;
        END IF;
        RETURN TRUE;
    EXCEPTION
        WHEN no_data_found THEN
            RETURN FALSE;
        WHEN OTHERS THEN
            printout('Error occurred in p050_is_valid_line:');
            printout(sqlcode || ': ' || sqlerrm);
    END p050_is_valid_line;


    -----------------------------------------------------------------------------
    -- parse input line and store in variables
    -----------------------------------------------------------------------------
    PROCEDURE p060_parse_input_line (
        p_input_line IN VARCHAR2
    ) IS
        lv_input_line VARCHAR2(2000) := p_input_line;
    BEGIN
        gv_customer_number := p040_get_next_token(lv_input_line); -- A
        gv_ordered_date := p040_get_next_token(lv_input_line); -- B
        gv_order_number := p040_get_next_token(lv_input_line); -- C
        gv_salesrep := p040_get_next_token(lv_input_line); -- D
        gv_line_number := p040_get_next_token(lv_input_line); -- E
        gv_inventory_item := p040_get_next_token(lv_input_line); -- F
        gv_ordered_quantity := p040_get_next_token(lv_input_line); -- G
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p060_parse_input_line:');
            printout(sqlcode || ': ' || sqlerrm);
    END p060_parse_input_line;


    -----------------------------------------------------------------------------
    -- look up org_id (do not hard-code as '82')
    -----------------------------------------------------------------------------
    PROCEDURE p071_get_org_id (
        p_org_id OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        SELECT
            COUNT(*)
        INTO lv_count
        FROM
            hr_operating_units
        WHERE
            name = c_operating_unit_name;

        IF lv_count = 0 THEN
            printout('p071_get_org_id: No records found in hr_operating_units for name = ' || c_operating_unit_name);
        ELSIF lv_count = 1 THEN
            SELECT
                organization_id
            INTO p_org_id
            FROM
                hr_operating_units
            WHERE
                name = c_operating_unit_name;

        ELSIF lv_count > 1 THEN
            printout('p071_get_org_id: More than one record found in hr_operating_units for name = ' || c_operating_unit_name);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p071_get_org_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p071_get_org_id;


    -----------------------------------------------------------------------------
    -- look up salesrep ID
    -----------------------------------------------------------------------------
    PROCEDURE p072_lookup_salesrep_id (
        p_salesrep    IN VARCHAR2,
        p_salesrep_id OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        IF isnumeric(p_salesrep) THEN
            p_salesrep_id := p_salesrep;
            RETURN;
        END IF;
        SELECT
            COUNT(*)
        INTO lv_count
        FROM
            fnd_dual
        WHERE
            1 = 1;

        IF lv_count > 0 THEN
            NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p072_lookup_salesrep_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p072_lookup_salesrep_id;


    -----------------------------------------------------------------------------
    -- look up sold-to org ID
    -- Added by VS 24-JAN-2023
    -----------------------------------------------------------------------------
    PROCEDURE p073_lookup_sold_to_org_id (
        p_customer_number       IN VARCHAR2,
        p_orig_system_reference OUT NUMBER,
        p_sold_to_org_id        OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        p_sold_to_org_id := NULL;
        SELECT DISTINCT
            COUNT(*)
        INTO lv_count
        FROM
            hz_cust_accounts
        WHERE
                1 = 1
--      orig_system_reference = p_customer_number;
            AND account_number = p_customer_number;

        IF lv_count = 0 THEN
            printout('p073_lookup_sold_to_org_id: No records found in hz_cust_accounts for customer number = ' || p_customer_number);
        ELSIF lv_count = 1 THEN
            SELECT DISTINCT
                orig_system_reference,
                cust_account_id
            INTO
                p_orig_system_reference,
                p_sold_to_org_id
            FROM
                hz_cust_accounts
            WHERE
                    1 = 1
--        orig_system_reference = p_customer_number;
                AND account_number = p_customer_number;

        ELSIF lv_count > 1 THEN
            printout('p073_lookup_sold_to_org_id: More than one record found in hz_cust_accounts for customer number = ' || p_customer_number);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p073_lookup_sold_to_org_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p073_lookup_sold_to_org_id;


  -----------------------------------------------------------------------------
  -- look up invoice-to org ID
  -----------------------------------------------------------------------------
    PROCEDURE p074_lookup_invoice_to_org_id (
        p_orig_system_reference IN NUMBER,
        p_invoice_to_org_id     OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        p_invoice_to_org_id := NULL;
        SELECT
            COUNT(DISTINCT site_use_id)
        INTO lv_count
        FROM
            hz_cust_site_uses_all
        WHERE
                1 = 1
            AND orig_system_reference = p_orig_system_reference
            AND site_use_code = 'BILL_TO';

        IF lv_count = 0 THEN
            printout('p074_lookup_invoice_to_org_id: No records found in hz_cust_site_uses_all for orig_system_reference = ' || p_orig_system_reference
            );
        ELSIF lv_count = 1 THEN
            SELECT DISTINCT
                site_use_id
            INTO p_invoice_to_org_id
            FROM
                hz_cust_site_uses_all
            WHERE
                    1 = 1
                AND orig_system_reference = p_orig_system_reference
                AND site_use_code = 'BILL_TO';

        ELSIF lv_count > 1 THEN
            printout('p074_lookup_invoice_to_org_id: More than one record found in hz_cust_site_uses_all for orig_system_reference = '
            || p_orig_system_reference);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p074_lookup_invoice_to_org_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p074_lookup_invoice_to_org_id;


  -----------------------------------------------------------------------------
  -- look up ship-to org ID
  -----------------------------------------------------------------------------
    PROCEDURE p075_lookup_ship_to_org_id (
        p_orig_system_reference IN NUMBER,
        p_ship_to_org_id        OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        p_ship_to_org_id := NULL;
        SELECT
            COUNT(DISTINCT site_use_id)
        INTO lv_count
        FROM
            hz_cust_site_uses_all
        WHERE
                1 = 1
            AND orig_system_reference = p_orig_system_reference
            AND site_use_code = 'SHIP_TO';

        IF lv_count = 0 THEN
            printout('p075_lookup_ship_to_org_id: No records found in hz_cust_site_uses_all for orig_system_reference = ' || p_orig_system_reference
            );
        ELSIF lv_count = 1 THEN
            SELECT DISTINCT
                site_use_id
            INTO p_ship_to_org_id
            FROM
                hz_cust_site_uses_all
            WHERE
                    1 = 1
                AND orig_system_reference = p_orig_system_reference
                AND site_use_code = 'SHIP_TO';

        ELSIF lv_count > 1 THEN
            printout('p075_lookup_ship_to_org_id: More than one record found in hz_cust_site_uses_all for orig_system_reference = ' |
            | p_orig_system_reference);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p075_lookup_ship_to_org_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p075_lookup_ship_to_org_id;


  -----------------------------------------------------------------------------
  -- look up inventory_item_id
  -- 31-JAN-2023 VS Added code to lookup inventory_item_id
  -----------------------------------------------------------------------------
    PROCEDURE p076_lookup_inventory_item_id (
        p_inventory_item    IN VARCHAR2,
        p_inventory_item_id OUT NUMBER
    ) IS
        lv_count NUMBER;
    BEGIN
        IF isnumeric(p_inventory_item) THEN
            p_inventory_item_id := TO_NUMBER ( p_inventory_item );
            RETURN;
        END IF;

        p_inventory_item_id := NULL;
        SELECT
            COUNT(DISTINCT inventory_item_id)
        INTO lv_count
        FROM
            mtl_item_locations
        WHERE
                1 = 1
            AND p_inventory_item = segment1 || '.' || segment2 || '.' || segment3;

        IF lv_count = 0 THEN
            printout('p076_lookup_inventory_item_id: No records found in mtl_item_locations for p_inventory_item = ' || p_inventory_item);
        ELSIF lv_count = 1 THEN
            SELECT DISTINCT
                inventory_item_id
            INTO p_inventory_item_id
            FROM
                mtl_item_locations
            WHERE
                    1 = 1
                AND p_inventory_item = segment1 || '.' || segment2 || '.' || segment3;

        ELSIF lv_count > 1 THEN
            printout('p076_lookup_inventory_item_id: More than one record found in mtl_item_locations for p_inventory_item = ' || p_inventory_item);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p076_lookup_inventory_item_id:');
            printout(sqlcode || ': ' || sqlerrm);
    END p076_lookup_inventory_item_id;


    -----------------------------------------------------------------------------
    -- get orig_sys_document_ref for each header
    -- modifed procedure to get updated
    -----------------------------------------------------------------------------
    PROCEDURE p077_get_orig_sys_doc_ref (
        p_curr_system_reference   IN VARCHAR2,
        p_prev_system_reference   IN OUT VARCHAR2,
        p_header_system_reference IN OUT NUMBER
    ) IS
        lv_curr_system_reference VARCHAR2(2000);
    BEGIN
        -- Added by VS 09-FEB-2024 To create unique identifier composed of customer number and order number
        lv_curr_system_reference := p_curr_system_reference || gv_order_number;
        IF p_prev_system_reference IS NULL OR p_prev_system_reference != lv_curr_system_reference THEN
            p_header_system_reference := hz_account_num_s.nextval;
        END IF;

        p_prev_system_reference := lv_curr_system_reference;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p077_get_orig_sys_doc_ref:');
            printout(sqlcode || ': ' || sqlerrm);
    END p077_get_orig_sys_doc_ref;


    -----------------------------------------------------------------------------
    -- get orig_sys_document_ref for each header
    -----------------------------------------------------------------------------
    PROCEDURE p078_get_other_ids (
        p_price_list    OUT VARCHAR2,
        p_order_type_id OUT NUMBER
    ) IS
        lv_db_name VARCHAR2(255);
    BEGIN
        SELECT
            name
        INTO lv_db_name
        FROM
            v$database;

        IF lv_db_name = 'TEST1' THEN
            p_price_list := 'XX_Price_List';					-- price list name on TEST1
            p_order_type_id := 1041;							-- BMOBILE ID on TEST1
        ELSE
            p_price_list := 'XX_LOCAL_PL_JMD (PRC02)';		    -- price list name on TEST1
            p_order_type_id := 1006;        					-- BMOBILE ID on TEST1
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p078_get_price_list:');
            printout(sqlcode || ': ' || sqlerrm);
    END p078_get_other_ids;


    -----------------------------------------------------------------------------
    -- look up all IDs
    -----------------------------------------------------------------------------
    PROCEDURE p080_lookup_ids IS
    BEGIN
        p071_get_org_id(lv_org_id);
        p072_lookup_salesrep_id(gv_salesrep, gn_salesrep_id);
        p073_lookup_sold_to_org_id(gv_customer_number, gv_orig_system_reference, gn_sold_to_org_id);
        p074_lookup_invoice_to_org_id(gv_orig_system_reference, gn_invoice_to_org_id);
        p075_lookup_ship_to_org_id(gv_orig_system_reference, gn_ship_to_org_id); -- (gv_ship_to_org, gn_ship_to_org_id);
        p076_lookup_inventory_item_id(gv_inventory_item, gn_inventory_item_id);
        p077_get_orig_sys_doc_ref(gv_orig_system_reference, gv_prev_system_reference, gn_orig_system_reference);
        p078_get_other_ids(gv_price_list, gv_order_type_id);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p080_lookup_ids:');
            printout(sqlcode || ': ' || sqlerrm);
    END p080_lookup_ids;


    -----------------------------------------------------------------------------
    -- print parsed tokens from input line (useful when debugging)
    -- CUSTOMER_NUMBER, ORDERED_DATE, SALESREP_ID, SOLD_TO_ORG_ID, INVOICE_TO_ORG_ID, SHIP_TO_ORG_ID, INVENTORY_ITEM_ID, ORDERED_QUANTITY
    -- ID columns that were looked up  are also printed
    -----------------------------------------------------------------------------
    PROCEDURE p090_print_input_fields IS
        lv_column VARCHAR2(1) := 'A';
        lv_blank  VARCHAR2(1) := '';
    BEGIN
        p000_print_token('CUSTOMER_NUMBER', lv_column, gv_customer_number);
        p000_print_token('ORDERED_DATE', lv_column, gv_ordered_date);
        p000_print_token('ORDER_NUMBER', lv_column, gv_order_number);
        p000_print_token('SALESREP', lv_column, gv_salesrep);
        p000_print_token('LINE_NUMBER', lv_column, gv_line_number);
        p000_print_token('INVENTORY_ITEM', lv_column, gv_inventory_item);
        p000_print_token('ORDERED_QUANTITY', lv_column, gv_ordered_quantity);
        p000_print_token('SALESREP_ID', lv_blank, gn_salesrep_id);
        p000_print_token('SOLD_TO_ORG_ID', lv_blank, gn_sold_to_org_id);
        p000_print_token('INVOICE_TO_ORG_ID', lv_blank, gn_invoice_to_org_id);
        p000_print_token('SHIP_TO_ORG_ID', lv_blank, gn_ship_to_org_id);
        p000_print_token('INVENTORY_ITEM_ID', lv_blank, gn_inventory_item_id);
        p000_print_token('GV_ORIG_SYSTEM_REFERENCE', lv_blank, gv_orig_system_reference);
        p000_print_token('GV_PREV_SYSTEM_REFERENCE', lv_blank, gv_prev_system_reference);
        p000_print_token('ORIG_SYS_DOCUMENT_REF', lv_blank, gn_orig_system_reference);
        p000_print_token('PRICE LIST', lv_blank, gv_price_list);
        p000_print_token('ORDER TYPE ID', lv_blank, gv_order_type_id);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p090_print_input_fields:');
            printout(sqlcode || ': ' || sqlerrm);
    END p090_print_input_fields;


    -----------------------------------------------------------------------------
    -- check if header row should be inserted
    -- if the current record matches the previous record, then do NOT insert
    -----------------------------------------------------------------------------
    PROCEDURE p095_chk_insert_header_flag IS
    BEGIN
        IF (
            gv_prev_customer_number = gv_customer_number
            AND gv_prev_ordered_date = gv_ordered_date
            AND gv_prev_order_number = gv_order_number
            AND gv_prev_salesrep = gv_salesrep
        ) THEN
            gb_insert_header_flag := FALSE;
        ELSE
            gb_insert_header_flag := TRUE;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p080_lookup_ids:');
            printout(sqlcode || ': ' || sqlerrm);
    END p095_chk_insert_header_flag;


    -----------------------------------------------------------------------------
    -- insert data into OE interface tables
    -- N.B. change IDs when you go to UAT3
    -- 31-JAN-2023 Added order_number
    -- 09-FEB-2024 Removed duplicate sold_from_org_id field from "INSERT INTO oe_headers_iface_all"
    -- 09-FEB-2024 Added sold_from_org_id field to "INSERT INTO oe_lines_iface_all"
    -----------------------------------------------------------------------------
    PROCEDURE p100_insert_tbl IS
    BEGIN
        IF gb_insert_header_flag = true THEN
            printout('Inserting header for order number: ' || gv_order_number);
            INSERT INTO oe_headers_iface_all (
                customer_number,
                ordered_date,
                order_number,
                salesrep_id,
                sold_to_org_id,
                invoice_to_org_id,
                ship_to_org_id,
                order_source_id,
                orig_sys_document_ref,
                org_id,
                order_type_id,
                price_list,
                operation_code,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                booked_flag
            ) VALUES (
                gv_customer_number,
                gv_ordered_date,
                gv_order_number, -- gv_order_number, -- should be a number, not varchar
                gn_salesrep_id,
                gn_sold_to_org_id,
                gn_invoice_to_org_id,
                gn_ship_to_org_id,
                '1001',                      -- order_source_id
                gn_orig_system_reference,    -- orig_sys_document_ref (WAS: gv_orig_system_reference)
                lv_org_id,                   -- org_id
                gv_order_type_id,                      -- order_type_id
                gv_price_list,           		-- price_list
                'INSERT',                    -- operation_code (WAS: BOOK)
                '1',                         -- created_by
                sysdate,                     -- creation_date
                '1',                         -- last_updated_by
                sysdate,                     -- last_update_date
                'Y'                          -- booked_flag
            );

        END IF;

        -- track fields from the last header row read
        gv_prev_customer_number := gv_customer_number;
        gv_prev_ordered_date := gv_ordered_date;
        gv_prev_order_number := gv_order_number;
        gv_prev_salesrep := gv_salesrep;
        INSERT INTO oe_lines_iface_all (
            inventory_item_id,
            ordered_quantity,
            order_source_id,
            orig_sys_document_ref,
            orig_sys_line_ref,
            line_number,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            operation_code,
            calculate_price_flag,
            org_id,
            sold_to_org_id
        ) VALUES (
            gn_inventory_item_id,        -- inventory_item_id
            gv_ordered_quantity,         -- ordered_quantity
            '1001',                      -- order_source_id
            gn_orig_system_reference,    -- orig_sys_document_ref (WAS: gv_orig_system_reference)
            gv_line_number,              -- orig_sys_line_ref
            gv_line_number,              -- line_number
            '1',                         -- created_by
            sysdate,                     -- creation_date
            '1',                         -- last_updated_by
            sysdate,                     -- last_update_date
            'INSERT',                    -- operation_code (WAS: BOOK)
            'Y',                         -- calculate_price_flag
            lv_org_id,                   -- org_id
            gn_sold_to_org_id            -- sold_from_org_id Added by VS 09-FEB-2024 as directed by NSingh
        );

    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p100_insert_tbl:');
            printout(sqlcode || ': ' || sqlerrm);
    END p100_insert_tbl;


  -----------------------------------------------------------------------------
  -- commit or rollback API call?
  -----------------------------------------------------------------------------
    PROCEDURE p110_commit_rollback (
        p_commit IN VARCHAR2
    ) IS
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
            printout('Error occurred in p110_commit_rollback:');
            printout(sqlcode || ': ' || sqlerrm);
    END p110_commit_rollback;


  -----------------------------------------------------------------------------
  -- print summary from load
  -----------------------------------------------------------------------------
    PROCEDURE p120_print_summary (
        p_total_rows_read IN NUMBER
    ) IS
    BEGIN
        printout(c_separator);
        printout('Total Records Read     : ' || lpad(p_total_rows_read, 4));
--    printout('# Rejected Lines       : ' || Lpad(p_rejected, 4));
--    printout('# Successful API Calls : ' || Lpad(p_success, 4));
--    printout('# Errored API Calls    : ' || Lpad(p_failure, 4));
        printout(rpad('----- Data file closed ', 80, '-'));
        printout(rpad('----- Load script is completed ', 80, '-'));
        printout(c_separator);
    EXCEPTION
        WHEN OTHERS THEN
            printout('Error occurred in p120_print_summary:');
            printout(sqlcode || ': ' || sqlerrm);
    END p120_print_summary;


--------------------------------------------------------------------------------
-- main driver
--------------------------------------------------------------------------------
BEGIN
    p010_print_parameters;
    oe_debug_pub.debug_on;
    oe_debug_pub.initialize;
    input_file := utl_file.fopen('AR_DATA_DIR', gp_filename, 'r');
    printout(rpad('----- Data file ' || gp_filename || ' opened ', 80, '-'));
  
    -- Added by VS 09-FEB-2024. Stop interface tables from being deleted.
    -- p015_delete_tbl;

    LOOP
        p020_read_next_line(input_file, ln_total_rows, lv_input_line, lb_no_data_found);
        IF lb_no_data_found THEN
            EXIT;
        ELSE
            p030_print_line(lv_input_line);
        END IF;
        p060_parse_input_line(lv_input_line);
        p080_lookup_ids;
        p090_print_input_fields;
        p095_chk_insert_header_flag;
        p100_insert_tbl;
    END LOOP;

    p110_commit_rollback(gp_commit);
    utl_file.fclose(input_file);
    p120_print_summary(ln_total_rows);
EXCEPTION
    WHEN le_invalid_file THEN
        printout('Invalid file operation: file not found?');
        printout(sqlcode || ': ' || sqlerrm);
    WHEN OTHERS THEN
        printout(sqlcode || ': ' || sqlerrm);
END;
/

SHOW ERRORS