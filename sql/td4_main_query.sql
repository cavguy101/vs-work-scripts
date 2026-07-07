-------------------------------------------------------------------------------
-- td4_main_query.sql
--------------------------------------------------------------------------------
-- This script contains the latest changes for the main query for the TD4 
-- report.
--------------------------------------------------------------------------------
-- Date         Author   Change
-- 24-MAR-2020  vseeram  Created
-- 26-MAR-2020  vseeram  Tuned query
--------------------------------------------------------------------------------

SELECT DISTINCT
    paaf.business_group_id,
    paaf.payroll_id,
    paaf.effective_start_date,
    paaf.effective_end_date,
    papf.person_id,
    paaf.primary_flag,
    papf.employee_number,
    paaf.assignment_status_type_id,
    papf.first_name || ' ' || papf.last_name            employee_name,
    papf.full_name,
    papf.attribute1              bir_file_number,
    papf.national_identifier     nis_number,
    ppg.segment1                 pay_station,
    hrou.name                    department,
    ppos.date_start              hire_date,
    ppos.actual_termination_date termination_date,
    paaf.assignment_id
FROM
    per_all_people_f       papf,
    per_all_assignments_f  paaf,
    pay_people_groups      ppg,
    per_periods_of_service ppos,
    hr_organization_units  hrou
WHERE
        1 = 1
    AND papf.person_id = paaf.person_id
    AND paaf.primary_flag = 'Y'
    AND TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR') BETWEEN papf.effective_start_date AND papf.effective_end_date
    AND papf.effective_start_date <= TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR')
    AND paaf.effective_start_date <= TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR')
    AND paaf.people_group_id = ppg.people_group_id
    AND ppg.segment1 = nvl(:p_region, ppg.segment1)
    AND paaf.payroll_id = :p_payroll_id
    AND papf.employee_number BETWEEN nvl(:p_from_employee_id, papf.employee_number) AND nvl(:p_to_employee_id, papf.employee_number)
    AND paaf.organization_id = hrou.organization_id
    AND hrou.organization_id = nvl(:p_department_id, hrou.organization_id)
    AND papf.person_id = ppos.person_id
    AND ( ppos.date_start ) IN (
        SELECT
            MAX(ppos1.date_start)
        FROM
            per_periods_of_service ppos1
        WHERE
                1 = 1
            AND ppos1.date_start <= TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR')
            AND papf.person_id = ppos1.person_id
    )
    AND ( ( :p_assignment_set_id IS NULL )
          OR ( paaf.assignment_id IN (
        SELECT
            hasa.assignment_id
        FROM
            hr_assignment_sets           has, hr_assignment_set_amendments hasa
        WHERE
                1 = 1
            AND has.assignment_set_id = hasa.assignment_set_id
            AND hasa.assignment_id = paaf.assignment_id
            AND hasa.include_or_exclude = 'I'
            AND has.assignment_set_id = nvl(:p_assignment_set_id, has.assignment_set_id)
    ) ) )
    AND EXISTS (
        SELECT
            papf1.person_id
        FROM
            per_all_people_f       papf1,
            per_all_assignments_f  paaf1,
            pay_assignment_actions paa1,
            pay_payroll_actions    ppa1
        WHERE
                1 = 1
            AND papf.person_id = papf1.person_id
            AND papf1.person_id = paaf1.person_id
            AND paaf1.assignment_id = paa1.assignment_id
            AND paa1.payroll_action_id = ppa1.payroll_action_id
            AND ppa1.effective_date BETWEEN TO_DATE('01-JAN-' || :p_year, 'DD-MON-RRRR') AND TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR'
            )
    )
    AND ( papf.person_id, paaf.effective_end_date ) IN (
        SELECT
            paaf2.person_id, MAX(paaf2.effective_end_date) max_end_date
        FROM
            per_all_assignments_f paaf2
        WHERE
                1 = 1
            AND paaf2.effective_start_date <= TO_DATE('31-DEC-' || :p_year, 'DD-MON-RRRR')
            AND paaf2.primary_flag = 'Y'
        GROUP BY
            paaf2.person_id
    )
ORDER BY
    papf.employee_number;
