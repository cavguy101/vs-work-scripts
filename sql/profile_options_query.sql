--------------------------------------------------------------------------------
-- profile_options_query.sql
--------------------------------------------------------------------------------
-- This script is used to search for a particular profile option in EBS. In the
-- WHERE clause, you can specify what value you want to search for. Several
-- commented examples are provided in the WHERE clause.
--------------------------------------------------------------------------------
-- vseeram  Created
--------------------------------------------------------------------------------
SELECT
    a.profile_option_id,
    b.user_profile_option_name, --  "Long Name",
    a.profile_option_name, --  "Short Name",
    c.level_id,
    c.level_value,
    decode(to_char(c.level_id),
           '10001',
           'Site',
           '10002',
           'Application',
           '10003',
           'Responsibility',
           '10004',
           'User',
           'Unknown')                                  "Level",
    g.responsibility_name,
    g.responsibility_key,
    decode(to_char(c.level_id),
           '10001',
           'Site',
           '10002',
           nvl(h.application_short_name,
               to_char(c.level_value)),
           '10003',
           nvl(g.responsibility_name,
               to_char(c.level_value)),
           '10004',
           nvl(e.user_name,
               to_char(c.level_value)),
           'Unknown')                                  "Level Value",
    c.profile_option_value                             "Profile Value",
    c.profile_option_id                                "Profile ID",
    to_char(c.last_update_date, 'DD-MON-YYYY HH24:MI') "Updated Date",
    nvl(d.user_name,
        to_char(c.last_updated_by))                    "Updated By"
FROM
    apps.fnd_profile_options       a,
    apps.fnd_profile_options_vl    b,
    apps.fnd_profile_option_values c,
    apps.fnd_user                  d,
    apps.fnd_user                  e,
    apps.fnd_responsibility_vl     g,
    apps.fnd_application           h
WHERE
        1 = 1
    AND a.profile_option_name = b.profile_option_name
    AND a.profile_option_id = c.profile_option_id
    AND a.application_id = c.application_id
    AND c.last_updated_by = d.user_id (+)
    AND c.level_value = e.user_id (+)
    AND c.level_value = g.responsibility_id (+)
    AND c.level_value = h.application_id (+)
    AND upper(b.user_profile_option_name) LIKE 'ASO%'
-- AND Upper(b.user_profile_option_name) LIKE 'RCV%'
-- AND Upper(b.user_profile_option_name) LIKE '%LOG%'
-- AND Upper(b.user_profile_option_name) LIKE 'FND%DEBUG%'
-- AND Upper(c.profile_option_value) LIKE '%HTTP%'
-- AND UPPER(b.user_profile_option_name) LIKE 'FSG%ALLOW%' -- check if FSG: Allow Portrait Print Style is set
-- AND a.profile_option_name LIKE 'RG%' -- RG_DEBUG_ON
-- AND UPPER(b.user_profile_option_name) LIKE 'FND%DIAG%'
-- AND UPPER(b.user_profile_option_name) LIKE 'FND%DEBUG%'
-- AND a.profile_option_name LIKE 'FND%DEBUG%'  -- check AME profiles
-- AND c.last_update_date >= To_DATE('01-JAN-2019', 'DD-MON-RRRR')
-- AND a.profile_option_name LIKE 'AME%'  -- check AME profiles
-- AND a.profile_option_name = 'HR_USER_TYPE' --   troubleshooting why Payroll field is read-only (HR_USER_TYPE)
-- AND c.level_id = '10003' AND a.profile_option_name = 'HR_USER_TYPE' --   troubleshooting why Payroll field is read-only (HR_USER_TYPE)
-- AND c.level_id = '10003' AND a.profile_option_name = 'PER_SECURITY_PROFILE_ID'
-- AND UPPER(b.user_profile_option_name) like '%GEO%'  -- troubleshoot Geography Hierarchy
-- AND a.profile_option_name LIKE '%GNR%'
-- AND UPPER(b.user_profile_option_name) like 'HZ:%'
-- AND UPPER(b.user_profile_option_name) like 'DATE%'
-- AND b.user_profile_option_name like 'FND%'
-- AND a.profile_option_name LIKE 'FND%'
-- AND b.user_profile_option_name like 'MO%'
-- AND b.user_profile_option_name like 'MO: Set Client_Info for Debugging'
-- AND a.profile_option_name = 'FND_MO_INIT_CI_DEBUG'
-- AND b.user_profile_option_name like '%Personal%'  -- while studying SSHR 
-- AND b.user_profile_option_name like 'HR%Actions%Menu'  -- while studying SSHR 
-- AND b.user_profile_option_name like 'ICX%'
-- AND UPPER(b.user_profile_option_name) like '%TIMEOUT%'
-- AND b.user_profile_option_name like 'ICX:Session Timeout'
-- AND b.user_profile_option_name = 'ICX: Forms Launcher'
-- AND A.profile_option_name like ('WF%')
-- AND b.user_profile_option_name in ('Server Timezone', 'Client Timezone')
-- AND c.profile_option_value LIKE '%jsp%'
-- AND b.user_profile_option_name LIKE '%WF%'
-- AND b.user_profile_option_name LIKE 'FND%Debug%'
-- AND b.user_profile_option_name LIKE 'AME%'
-- AND b.user_profile_option_name in ('ICX:Session Timeout', 'ICX: Limit connect', 'ICX: Limit time')
-- AND b.user_profile_option_name in ('Customer Care: Turn On Interaction Logging in Contact Center', 'Customer Care: Turn On Logging of Task Activities')
-- AND upper(b.user_profile_option_name) like ('%LOG%')
/*
AND (
  upper(b.user_profile_option_name) LIKE '%DEBUG%'
OR upper(b.user_profile_option_name) LIKE '%TRACE%'
OR upper(b.user_profile_option_name) LIKE '%LOGG%'
)
*/
ORDER BY
    c.last_update_date DESC,
    b.user_profile_option_name,
    c.level_id,
    decode(to_char(c.level_id),
           '10001',
           'Site',
           '10002',
           nvl(h.application_short_name,
               to_char(c.level_value)),
           '10003',
           nvl(g.responsibility_name,
               to_char(c.level_value)),
           '10004',
           nvl(e.user_name,
               to_char(c.level_value)),
           'Unknown');