--------------------------------------------------------------------------------
-- payroll_dump_query.sql
--------------------------------------------------------------------------------
-- Payroll Elements Dump Query concurrent request
--------------------------------------------------------------------------------
-- Dump of elements for each employee on payroll
-- SQL originally provided by AMahalingam
--------------------------------------------------------------------------------
-- Parameters:
-- 1 = payroll_id e.g. 61
-- 2 = time_period_id e.g. 97
-- 3 = consolidation_set_id e.g. 1065
-- 4 = payroll action id e.g. 67425
--------------------------------------------------------------------------------
-- Date Modified  By  Change
-- 29-AUG-2017    VS  Removed per_person_type_usages_f and per_person_types,
--                    which checks if person_type is 'Emp'
--                    (employee_number = '24187')
-- 26-OCT-2017    VS  Changed code for effective_end_date to 
--                    least(effective_date, effective_end_date)
-- 30-OCT-2017    VS  Adjusted column widths for element_name, reporting_name
-- 06-DEC-2017    VS  Include consolidation set; SET termout OFF to prevent
--                    output from displaying in log file
-- 20-MAY-2018    VS  Removed WHERE clause "AND ppa.action_type = 'R'" 
--                    to allow QuickPay payments to appear in report
--                    Cleaned up SQL code
-- 18-OCT-2019    VS  Added condition "AND ppa.payroll_action_id = NVL('&4', ppa.payroll_action_id)"
--                    Enter the Run ('R') payroll action ID, not Prepayments ('P')
--------------------------------------------------------------------------------

SET HEADING ON
SET VERIFY OFF
SET LINESIZE 5000
SET TRIMSPOOL ON
SET TERMOUT OFF
SET FEEDBACK ON

COL employee_number FORMAT A15
COL assignment_number FORMAT A17
COL primary_flag FORMAT A12
COL effective_start_date FORMAT A10 HEADING 'START_DATE'
COL element_name FORMAT A70
COL reporting_name FORMAT A70
COL classification_name FORMAT A20
COL pay_value FORMAT 999,999,990.00

SELECT
    papf.employee_number,
    paaf.assignment_number,
    paaf.primary_flag,
    paaf.effective_start_date,
    petf.element_name              element_name,
    petf.reporting_name            reporting_name,
    pec.classification_name        classification_name,
    SUM(nvl(prrv.result_value, 0)) pay_value
FROM
    per_all_people_f            papf,
    per_all_assignments_f       paaf,
    pay_assignment_actions      paa,
    pay_payroll_actions         ppa,
    pay_run_results             prr,
    pay_run_result_values       prrv,
    pay_input_values_f          pivf,
    pay_element_types_f         petf,
    pay_element_classifications pec,
    per_time_periods            ptp
WHERE
        1 = 1
    AND papf.person_id = paaf.person_id
    AND paaf.business_group_id = 81
    AND paaf.payroll_id = '&1'
    AND paaf.assignment_id = paa.assignment_id
    AND paa.payroll_action_id = ppa.payroll_action_id
    AND ppa.payroll_id = paaf.payroll_id
    AND paaf.payroll_id = ptp.payroll_id
    AND ptp.time_period_id = '&2'
    AND ptp.time_period_id = ppa.time_period_id
    AND ppa.effective_date BETWEEN ptp.start_date AND ptp.end_date
    AND ptp.end_date BETWEEN papf.effective_start_date AND least(ptp.end_date, papf.effective_end_date)
    AND ptp.end_date BETWEEN paaf.effective_start_date AND least(ptp.end_date, paaf.effective_end_date)
    AND ptp.end_date BETWEEN pivf.effective_start_date AND least(ptp.end_date, pivf.effective_end_date)
    AND ptp.end_date BETWEEN petf.effective_start_date AND least(ptp.end_date, petf.effective_end_date)
    AND paa.assignment_action_id = prr.assignment_action_id
    AND prr.run_result_id = prrv.run_result_id
    AND prrv.input_value_id = pivf.input_value_id
    AND pivf.name = 'Pay Value'
    AND prr.element_type_id = petf.element_type_id
    AND petf.classification_id = pec.classification_id
    AND ppa.consolidation_set_id = '&3'
    AND ppa.payroll_action_id = nvl('&4', ppa.payroll_action_id) 
GROUP BY
    papf.employee_number,
    paaf.assignment_number,
    paaf.primary_flag,
    paaf.effective_start_date,
    petf.element_name,
    petf.reporting_name,
    pec.classification_name,
    prrv.result_value
ORDER BY
    papf.employee_number,
    paaf.assignment_number,
    pec.classification_name,
    petf.element_name ASC;
    
    