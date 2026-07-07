--------------------------------------------------------------------------------
--  AP_TPD_REPORT.sql
--------------------------------------------------------------------------------
--  Generate report for the third party deductions
--------------------------------------------------------------------------------
--  Change List
--  ===========
--  1.0    28-MAR-2017     rramrattan     Created
--  2.0    22-JUN-2017     vseeram        Added 'NO TAX' to be checked in
--                                        apss.vendor_site_code
--  3.0    29-JUN-2017     vseeram        Changed 'COLUMN assignment' to suppress
--                                        when no assignment set is specified
--  4.0    08-JAN-2018     vseeram        Changed 'sum(amount)' in COLUMN and COMPUTE 
--                                        statements to 'amount'
--------------------------------------------------------------------------------
SET ECHO OFF

SET PAGESIZE 44
SET LINESIZE 200
SET VERIFY OFF
SET TRIMSPOOL ON
SET WRAP OFF
SET FEEDBACK OFF
CLEAR COLUMNS
CLEAR BREAKS

COLUMN startdate NOPRINT NEW_VALUE startdate
COLUMN enddate NOPRINT NEW_VALUE enddate
COLUMN payroll NOPRINT NEW_VALUE payroll
COLUMN consolidation NOPRINT NEW_VALUE consolidation
COLUMN assignment NOPRINT NEW_VALUE assignment

SELECT
    start_date startdate,
    end_date   enddate
FROM
    per_time_periods
WHERE
    time_period_id = '&2';

SELECT
    payroll_name payroll
FROM
    pay_all_payrolls_f
WHERE
    payroll_id = '&1';

SELECT
    consolidation_set_name consolidation
FROM
    pay_consolidation_sets
WHERE
    consolidation_set_id = '&3';

SELECT
    assignment_set_name assignment
FROM
    hr_assignment_sets
WHERE
    assignment_set_id = '&4';

BREAK ON REPORT
COMPUTE COUNT LABEL "number_of_suppliers" OF main_office ON REPORT
COMPUTE SUM LABEL "total" OF amount ON REPORT

COLUMN main_office FORMAT a100 HEADING "main office"
COLUMN vendor_num FORMAT a14 HEADING "vendor number"
COLUMN invoice_number FORMAT a15 HEADING "invoice number"
COLUMN amount FORMAT 999,999,990.00 HEADING "total amount"

TTITLE col 20 'TEST PAYROLL RUN' SKIP 2 -
'PAY GROUP         : ' payroll SKIP 1 -
'CONSOLIDATION SET : ' consolidation SKIP 1 -
'ASSIGNMENT SET    : ' assignment SKIP 1 -
'FROM              : ' startdate ' TO: ' enddate SKIP 1 -
'REQUESTED BY      : ' '&5' COL 30 'RUN DATE: ' _DATE SKIP 2
SET heading ON

SELECT
    main_office,
    total.vendor_num,
    total.invoice_number,
    amount
FROM
    (
        SELECT
            main_office,
            vendor_num,
            invoice_number,
            SUM(amount) amount
        FROM
            (
                SELECT
                    ven.vendor_name               main_office,
                    ven.vendor_num,
                    paaf.person_id,
                    paaf.assignment_number,
                    aii.invoice_num               invoice_number,
                    ( nvl(prrv.result_value, 0) ) amount
                FROM
                    pay_run_results             prr,
                    pay_run_result_values       prrv,
                    pay_input_values_f          pivf,
                    pay_element_types_f         petf,
                    pay_element_classifications pec,
                    pay_assignment_actions      paa,
                    pay_payroll_actions         ppa,
                    per_all_assignments_f       paaf,
                    pay_all_payrolls_f          pasf,
                    pay_consolidation_sets      pcs,
                    per_time_periods            ptp,
                    ap_invoices_interface       aii,
                    (
                        SELECT
                            aps.vendor_id,
                            aps.segment1 vendor_num,
                            vendor_name,
                            apss.vendor_site_id,
                            apss.vendor_site_code
                        FROM
                            ap_suppliers          aps,
                            ap_supplier_sites_all apss
                        WHERE
                                aps.vendor_id = apss.vendor_id
                            AND upper(apss.vendor_site_code) IN ( 'NO TAX', 'NO TAX SITE' )
                    )  ven
                WHERE
                        paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.payroll_id = &1
                    AND ppa.payroll_id = ptp.payroll_id
                    AND pasf.payroll_id = ppa.payroll_id
                    AND ptp.time_period_id = &2
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND ppa.consolidation_set_id = &3
                    AND paaf.assignment_id = paa.assignment_id
                    AND ( ( ppa.assignment_set_id IS NULL )
                          OR ( paaf.assignment_id IN (
                        SELECT
                            hasa.assignment_id
                        FROM
                            hr_assignment_set_amendments hasa
                        WHERE
                                hasa.assignment_id = paaf.assignment_id
                            AND hasa.assignment_set_id = nvl('&4', hasa.assignment_set_id)
                    ) ) )
                    AND prr.element_type_id = petf.element_type_id
                    AND prr.run_result_id = prrv.run_result_id
                    AND prrv.input_value_id = pivf.input_value_id
                    AND petf.classification_id = pec.classification_id
                    AND pivf.name = 'Pay Value'
                    AND pec.classification_name IN ( 'Voluntary Deductions', 'Involuntary Deductions' )
                    AND prr.assignment_action_id = paa.assignment_action_id
                    AND paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.effective_date BETWEEN ptp.start_date AND ptp.end_date
                    AND aii.vendor_id (+) = ven.vendor_id
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND ppa.effective_date BETWEEN pivf.effective_start_date AND least(ppa.effective_date, pivf.effective_end_date)
                    AND ppa.effective_date BETWEEN paaf.effective_start_date AND least(ppa.effective_date, paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN petf.effective_start_date AND least(ppa.effective_date, petf.effective_end_date)
                    AND ven.vendor_id = TO_NUMBER(petf.attribute5)
                    AND paaf.person_id = nvl('&6', paaf.person_id)
                    AND ppa.action_type = nvl('&7', ppa.action_type)
            )
        GROUP BY
            main_office,
            invoice_number,
            vendor_num
        HAVING
            SUM(nvl(amount, 0)) > 0
    ) total,
    ap_invoices_interface ai
WHERE
        ai.invoice_amount = total.amount
    AND ai.invoice_num = total.invoice_number
UNION
SELECT
    main_office,
    total.vendor_num,
    total.invoice_number,
    amount
FROM
    (
        SELECT
            main_office,
            vendor_num,
            invoice_number,
            SUM(amount) amount
        FROM
            (
                SELECT
                    ven.vendor_name               main_office,
                    ven.vendor_num,
                    paaf.person_id,
                    paaf.assignment_number,
                    aii.invoice_num               invoice_number,
                    ( nvl(prrv.result_value, 0) ) amount
                FROM
                    pay_run_results             prr,
                    pay_run_result_values       prrv,
                    pay_input_values_f          pivf,
                    pay_element_types_f         petf,
                    pay_element_classifications pec,
                    pay_assignment_actions      paa,
                    pay_payroll_actions         ppa,
                    per_all_assignments_f       paaf,
                    pay_all_payrolls_f          pasf,
                    pay_consolidation_sets      pcs,
                    per_time_periods            ptp,
                    ap_invoices_interface       aii,
                    (
                        SELECT
                            aps.vendor_id,
                            aps.segment1 vendor_num,
                            vendor_name,
                            apss.vendor_site_id,
                            apss.vendor_site_code
                        FROM
                            ap_suppliers          aps,
                            ap_supplier_sites_all apss
                        WHERE
                                aps.vendor_id = apss.vendor_id
                            AND upper(apss.vendor_site_code) IN ( 'NO TAX', 'NO TAX SITE' )
                    )                           ven
                WHERE
                        paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.payroll_id = &1
                    AND ppa.payroll_id = ptp.payroll_id
                    AND pasf.payroll_id = ppa.payroll_id
                    AND ptp.time_period_id = &2
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND ppa.consolidation_set_id = &3
                    AND paaf.assignment_id = paa.assignment_id
                    AND ( ( ppa.assignment_set_id IS NULL )
                          OR ( paaf.assignment_id IN (
                        SELECT
                            hasa.assignment_id
                        FROM
                            hr_assignment_set_amendments hasa
                        WHERE
                                hasa.assignment_id = paaf.assignment_id
                            AND hasa.assignment_set_id = nvl('&4', hasa.assignment_set_id)
                    ) ) )
                    AND prr.element_type_id = petf.element_type_id
                    AND prr.run_result_id = prrv.run_result_id
                    AND prrv.input_value_id = pivf.input_value_id
                    AND petf.classification_id = pec.classification_id
                    AND pivf.name = 'Pay Value'
                    AND pec.classification_name = 'Employer Charges'
                    AND prr.assignment_action_id = paa.assignment_action_id
                    AND paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.effective_date BETWEEN ptp.start_date AND ptp.end_date
                    AND aii.vendor_id (+) = ven.vendor_id
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND ppa.effective_date BETWEEN pivf.effective_start_date AND least(ppa.effective_date, pivf.effective_end_date)
                    AND ppa.effective_date BETWEEN paaf.effective_start_date AND least(ppa.effective_date, paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN petf.effective_start_date AND least(ppa.effective_date, petf.effective_end_date)
                    AND ven.vendor_id = TO_NUMBER(petf.attribute5)
                    AND paaf.person_id = nvl('&6', paaf.person_id)
                    AND ppa.action_type = nvl('&7', ppa.action_type)
            )
        GROUP BY
            main_office,
            invoice_number,
            vendor_num
        HAVING
            SUM(nvl(amount, 0)) > 0
    )  total,
    ap_invoices_interface ai
WHERE
        ai.invoice_amount = total.amount
    AND ai.invoice_num = total.invoice_number
ORDER BY
    invoice_number ASC NULLS FIRST,
    main_office;

CLEAR COLUMNS
CLEAR BREAKS
TTITLE OFF
SET VERIFY ON
SET FEEDBACK ON