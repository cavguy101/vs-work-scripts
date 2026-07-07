-------------------------------------------------------------------------------
-- ar_receipts_api_test2.sql
-- This script loads a single row using the AR_RECEIPT_API_PUB API.create_cash call
-- Reference: http://www.shareoracleapps.com/2011/01/arreceiptapipub-script-to-create-and.html
-- org_id = 101
-------------------------------------------------------------------------------

SET SERVEROUTPUT ON

DECLARE
    v_return_status     VARCHAR2(1);
    v_msg_count         NUMBER;
    v_msg_data          VARCHAR2(240);
    v_count             NUMBER;
    v_cash_receipt_id   NUMBER;
    v_msg_data_out      VARCHAR2(240);
    v_mesg              VARCHAR2(240);
    p_count             NUMBER;
    v_currency_code     VARCHAR2(5);
    v_amount            NUMBER;
    v_receipt_number    VARCHAR2(30);
    v_receipt_date      DATE;
    v_gl_date           DATE;
    v_customer_number   VARCHAR2(30);
    v_receipt_method_id NUMBER;
    v_org_id            NUMBER;
    v_context           VARCHAR2(100);

    FUNCTION set_context (
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
            RETURN 'F';
    END set_context;


BEGIN

    -- Set applications context if not already set.
    v_context := set_context('M_TESTUSER', 'Receivables Manager', 101);
    IF v_context = 'F' THEN
        dbms_output.put_line('Error while setting the context');
    END IF;
--  mo_global.init('AR');

    -- Initialising the input parameters
    v_currency_code := 'USD';
    v_amount := 100;
    v_receipt_number := 'VSTEST1';
    v_receipt_date := trunc(sysdate);
    v_gl_date := trunc(sysdate);
    v_customer_number := '98765';
    v_receipt_method_id := 3001; -- USD - Direct Deposit;
    v_org_id := 101;
    ar_receipt_api_pub.create_cash(
        p_api_version => 1.0, 
        p_init_msg_list => fnd_api.g_true, 
        p_commit => fnd_api.g_false, 
        p_validation_level => fnd_api.g_valid_level_full, 
        x_return_status => v_return_status,
        x_msg_count => v_msg_count, 
        x_msg_data => v_msg_data, 
        p_currency_code => v_currency_code, 
        p_amount => v_amount, 
        p_receipt_number => v_receipt_number,
        p_receipt_date => v_receipt_date, 
        p_gl_date => v_gl_date, 
        p_customer_number => v_customer_number, 
        p_receipt_method_id => v_receipt_method_id, 
        p_cr_id => v_cash_receipt_id
    );

    IF v_return_status = 'S' THEN
        dbms_output.put_line('Receipt Creation and apply on account is Successful :' || v_cash_receipt_id);
    ELSE
        dbms_output.put_line('Message count ' || v_msg_count);
        IF v_msg_count = 1 THEN
            dbms_output.put_line('v_msg_data ' || v_msg_data);
        ELSIF v_msg_count > 1 THEN
            LOOP
                p_count := p_count + 1;
                v_msg_data := fnd_msg_pub.get(fnd_msg_pub.g_next, fnd_api.g_false);
                IF v_msg_data IS NULL THEN
                    EXIT;
                END IF;
                dbms_output.put_line('Message' || p_count || '---' || v_msg_data);
            END LOOP;
        END IF;

    END IF;

    ROLLBACK;
END;
/
