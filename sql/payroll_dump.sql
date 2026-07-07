--------------------------------------------------------------------------------
-- payroll_dump.sql
--------------------------------------------------------------------------------
-- Dump of elements for each employee on payroll
--------------------------------------------------------------------------------
-- 17-AUG-2017  vseeram
--------------------------------------------------------------------------------
SELECT
    ppf.employee_number,
    paf.assignment_number,
    paf.primary_flag,
    paf.effective_start_date,
    petf.element_name              element_name,
    petf.reporting_name            reporting_name,
    pec.classification_name        classification_name,
    SUM(nvl(prrv.result_value, 0)) pay_value
FROM
    per_people_f                ppf,
    per_assignments_f           paf,
    per_person_types            ppt,
    per_person_type_usages_f    pputf,
    per_periods_of_service      ppos,
    hr_organization_units       hrou,
    pay_assignment_actions      paa,
    pay_payroll_actions         ppa,
    pay_run_results             prr,
    pay_run_result_values       prrv,
    pay_input_values_f          pivf,
    pay_element_types_f         petf,
    pay_element_classifications pec,
    per_grades                  pg,
    per_grade_definitions       pgd,
    pay_people_groups           ppg,
    per_time_periods            ptp
WHERE
        1 = 1
    AND ppf.person_id = paf.person_id
    AND paf.business_group_id = 81
    AND ppf.person_id = ppos.person_id
    AND ppf.person_id = pputf.person_id
    AND pputf.person_type_id = ppt.person_type_id
    AND ppt.system_person_type = 'EMP'
    AND paf.organization_id = hrou.organization_id
    AND paf.payroll_id = &p_payroll_id
    AND paf.assignment_id = paa.assignment_id
    AND paa.payroll_action_id = ppa.payroll_action_id
    AND ppa.action_type = 'R'
    AND ptp.time_period_id = &p_time_period_id
    AND ppa.effective_date BETWEEN ptp.start_date AND ptp.end_date
    AND ppa.effective_date BETWEEN ppf.effective_start_date AND ppf.effective_end_date
    AND ppa.effective_date BETWEEN paf.effective_start_date AND paf.effective_end_date
    AND ppa.effective_date BETWEEN pputf.effective_start_date AND pputf.effective_end_date
    AND prr.assignment_action_id = paa.assignment_action_id
    AND prr.element_type_id = petf.element_type_id
    AND prr.run_result_id = prrv.run_result_id
    AND prrv.input_value_id = pivf.input_value_id
    AND petf.classification_id = pec.classification_id
    AND pivf.name = 'Pay Value'
    AND ptp.end_date BETWEEN pivf.effective_start_date AND pivf.effective_end_date
    AND ptp.end_date BETWEEN petf.effective_start_date AND petf.effective_end_date
    AND paf.grade_id = pg.grade_id (+)
    AND pg.grade_definition_id = pgd.grade_definition_id (+)
    AND paf.people_group_id = ppg.people_group_id (+)
GROUP BY
    ppf.employee_number,
    paf.assignment_number,
    paf.primary_flag,
    paf.effective_start_date,
    petf.element_name,
    petf.reporting_name,
    pec.classification_name,
    prrv.result_value
ORDER BY
    ppf.employee_number,
    paf.assignment_number,
    pec.classification_name,
    petf.element_name ASC;


    