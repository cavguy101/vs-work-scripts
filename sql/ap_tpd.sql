REM ----------------------------------------------------------------------------
REM AP_TPD.sql
REM Spool third party deductions to pay by cheque into thirdpartydeductions.csv
REM for loading into the AP invoice interface tables
REM ----------------------------------------------------------------------------
REM
REM Change List
REM ===========
REM 1    28-MAR-2017   rramrattan   Created
REM ...
REM 2    31-JAN-2018   vseeram      Removed $0 invoice amounts from output
REM  
SET NEWPAGE NONE
SET HEADING OFF
SET COLSEP ", "
SET VERIFY OFF
SET PAGESIZE 500
SET LINESIZE 5000
SET TRIMSPOOL ON

COL vendor_site_id FORMAT 9999999
COL vendor_name FORMAT a30

DELETE FROM
  ap_invoice_lines_interface
WHERE
  invoice_id in (
  SELECT
     invoice_id
  FROM
      ap_invoices_interface
  WHERE
    1 = 1
  AND invoice_num LIKE 'XXPAY%'
  AND invoice_type_lookup_code = 'STANDARD'
  AND source = 'XXPAYROLLTHIRDPARTY'
);

DELETE FROM
    ap_invoices_interface
WHERE
    1 = 1
AND invoice_num LIKE 'XXPAY%'
AND invoice_type_lookup_code = 'STANDARD'
AND source = 'XXPAYROLLTHIRDPARTY'
;

COMMIT;

SPOOL thirdpartydeductions.CSV REP

SELECT
    ap_invoices_interface_s.NEXTVAL,
    invoice_date,
    vendor_id,
    vendor_site_id,
    terms_date,
    amount,
    gl_date,
    'XXPAY' || invoice_num_pay_seq.NEXTVAL,
    ap_invoices_interface_s.CURRVAL,
    amount,
    distribution_set_name
FROM
    (
        SELECT
            invoice_date,
            gl_date,
            vendor_id,
            vendor_num,
            main_office,
            vendor_site_id,
            vendor_site_code,
            terms_date,
            SUM(nvl(amount, 0)) amount,
            distribution_set_name
        FROM
            (
                SELECT
                    sysdate                                                      invoice_date,
                    to_char(TO_DATE('&5', 'yyyy/mm/dd HH24:MI:SS'), 'DD-MON-YY') gl_date,
                    ven.vendor_id,
                    ven.vendor_num,
                    ven.vendor_name                                              main_office,
                    ven.vendor_site_id,
                    ven.vendor_site_code,
                    sysdate                                                      terms_date,
                    paaf.assignment_number,
                    ( nvl(prrv.result_value, 0) )                                amount,
                    '"'
                    ||
                    CASE
                            WHEN pasf.payroll_name = 'Executive'   THEN
                                'XX SALARIES NET PAY ACCOUNT'
                            WHEN pasf.payroll_name = 'XXM'       THEN
                                'XX SALARIES NET PAY ACCOUNT'
                            WHEN pasf.payroll_name = 'DNTH'        THEN
                                'XX SALARIES NET PAY ACCOUNT'
                            WHEN pasf.payroll_name = 'Fortnightly' THEN
                                'XX WAGES NET PAY ACCOUNT'
                            WHEN pasf.payroll_name = 'NSDP'        THEN
                                'XX WAGES NET PAY ACCOUNT'
                            WHEN pasf.payroll_name = 'Trainee'     THEN
                                'XX WAGES NET PAY ACCOUNT'
                            ELSE
                                ''
                    END
                    || '"'                                                       distribution_set_name
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
                    (
                        SELECT
                            aps.vendor_id,
                            aps.segment1 vendor_num,
                            vendor_name,
                            apss.vendor_site_id,
                            apss.vendor_site_code,
                            apss.inactive_date,
                            aps.start_date_active,
                            aps.end_date_active
                        FROM
                            ap_suppliers          aps,
                            ap_supplier_sites_all apss
                        WHERE
                                aps.vendor_id = apss.vendor_id
                            AND upper(apss.vendor_site_code) = upper('NO TAX')
                                AND apss.inactive_date IS NULL
                                    AND sysdate BETWEEN aps.start_date_active AND nvl(aps.end_date_active, sysdate)
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
                    AND ( ( '&4' IS NULL )
                      OR ( paaf.assignment_id IN (
                            SELECT
                                hasa.assignment_id
                            FROM
                                hr_assignment_set_amendments hasa
                            WHERE
                                    hasa.assignment_id = paaf.assignment_id
                                AND hasa.assignment_set_id = nvl('&4', hasa.assignment_set_id)
                            ) 
                        ) 
                    )
                    AND prr.element_type_id = petf.element_type_id
                    AND prr.run_result_id = prrv.run_result_id
                    AND prrv.input_value_id = pivf.input_value_id
                    AND petf.classification_id = pec.classification_id
                    AND pivf.name = 'Pay Value'
                    AND pec.classification_name IN ( 'Voluntary Deductions', 'Involuntary Deductions')
                    AND prr.assignment_action_id = paa.assignment_action_id
                    AND paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.effective_date BETWEEN ptp.start_date AND
                    ptp.end_date
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND petf.attribute5 = to_char(ven.vendor_id)
                    --AND ptp.end_date BETWEEN paaf.effective_start_date AND last_day(paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN pivf.effective_start_date AND least(ppa.effective_date, pivf.effective_end_date)
                    AND ppa.effective_date BETWEEN paaf.effective_start_date AND least(ppa.effective_date, paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN petf.effective_start_date AND least(ppa.effective_date, petf.effective_end_date)
                    AND paaf.person_id = nvl('&6', paaf.person_id)
                    AND ppa.action_type = nvl('&7', ppa.action_type)
            )
        GROUP BY
            invoice_date,
            gl_date,
            vendor_id,
            vendor_num,
            main_office,
            vendor_site_id,
            vendor_site_code,
            terms_date,
            distribution_set_name
        HAVING
            SUM(nvl(amount, 0)) > 0
        UNION ALL
        SELECT
            invoice_date,
            gl_date,
            vendor_id,
            vendor_num,
            main_office,
            vendor_site_id,
            vendor_site_code,
            terms_date,
            SUM(nvl(amount, 0)) amount,
            distribution_set_name
        FROM
            (
                SELECT
                    sysdate                                                      invoice_date,
                    to_char(TO_DATE('&5', 'yyyy/mm/dd HH24:MI:SS'), 'DD-MON-YY') gl_date,
                    ven.vendor_id,
                    ven.vendor_num,
                    ven.vendor_name                                              main_office,
                    ven.vendor_site_id,
                    ven.vendor_site_code,
                    sysdate                                                      terms_date,
                    paaf.assignment_number,
                    ( nvl(prrv.result_value, 0) )                                amount,
                    '"'
                    ||
                    CASE
                            WHEN petf.element_name = 'MM INSURANCE EMPLOYER CONTRIBUTION 6624'      THEN
                                'MM INSURANCE EMPLOYER CONTRIBUTION 6624'
                            WHEN petf.element_name = 'MM INSURANCE EMPLOYER CONTRIBUTION M 6625'    THEN
                                'MM INSURANCE EMPLOYER CONTRIBUTION M 6625'
                            WHEN petf.element_name = 'NIS EMPLOYER CONTRIBUTION'
                                 AND pasf.payroll_name IN ( 'DNTH', 'Fortnightly', 'NSDP', 'Trainee' ) THEN
                                'NIS EMPLOYER CONTRIBUTION-DP'
                            WHEN petf.element_name = 'NIS EMPLOYER CONTRIBUTION'
                                 AND pasf.payroll_name IN ( 'Executive', 'XXM' ) THEN
                                'NIS EMPLOYER CONTRIBUTION-MP'
                            WHEN petf.element_name = 'XX PENSION SCHEME DP EMPLOYER CONTRIBUTION' THEN
                                'XX PENSION SCHEME DP EMPLOYER CONTRIBUTION'
                            WHEN petf.element_name = 'XX PENSION SCHEME MP EMPLOYER CONTRIBUTION' THEN
                                'XX PENSION SCHEME MP EMPLOYER CONTRIBUTION'
                            ELSE
                                ''
                    END
                    || '"'                                                       distribution_set_name
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
                    (
                        SELECT
                            aps.vendor_id,
                            aps.segment1 vendor_num,
                            vendor_name,
                            apss.vendor_site_id,
                            apss.vendor_site_code,
                            apss.inactive_date,
                            aps.start_date_active,
                            aps.end_date_active
                        FROM
                            ap_suppliers          aps,
                            ap_supplier_sites_all apss
                        WHERE
                                aps.vendor_id = apss.vendor_id
                            AND upper(apss.vendor_site_code) = upper('NO TAX')
                                AND apss.inactive_date IS NULL
                                    AND sysdate BETWEEN aps.start_date_active AND nvl(aps.end_date_active, sysdate)
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
                    AND ( ( '&4' IS NULL )
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
                    AND pec.classification_name = ( 'Employer Charges' )
                    AND prr.assignment_action_id = paa.assignment_action_id
                    AND paa.payroll_action_id = ppa.payroll_action_id
                    AND ppa.effective_date BETWEEN ptp.start_date AND
                    ptp.end_date
                    AND pcs.consolidation_set_id = ppa.consolidation_set_id
                    AND petf.attribute5 = to_char(ven.vendor_id)
                    --AND ptp.end_date BETWEEN paaf.effective_start_date AND last_day(paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN pivf.effective_start_date AND least(ppa.effective_date, pivf.effective_end_date)
                    AND ppa.effective_date BETWEEN paaf.effective_start_date AND least(ppa.effective_date, paaf.effective_end_date)
                    AND ppa.effective_date BETWEEN petf.effective_start_date AND least(ppa.effective_date, petf.effective_end_date)
                    AND paaf.person_id = nvl('&6', paaf.person_id)
                    AND ppa.action_type = nvl('&7', ppa.action_type)
            )
        GROUP BY
            invoice_date,
            gl_date,
            vendor_id,
            vendor_num,
            main_office,
            vendor_site_id,
            vendor_site_code,
            terms_date,
            distribution_set_name
        HAVING
            SUM(nvl(amount, 0)) > 0
        ORDER BY
            1
    );

SPOOL OFF