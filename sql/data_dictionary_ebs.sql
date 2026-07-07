--------------------------------------------------------------------------------
-- data_dictionary_ebs.sql
--------------------------------------------------------------------------------
-- This script stores frequently used EBS R12.2 tables.
--------------------------------------------------------------------------------
-- 20-FEB-2024  vseeram  Created
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. GL tables
--------------------------------------------------------------------------------
SELECT * FROM gl_je_batches;
SELECT * FROM gl_je_headers;
SELECT * FROM gl_je_lines;
SELECT * FROM gl_ledgers;
SELECT * FROM gl_code_combinations;
SELECT * FROM gl_interface;
SELECT * FROM gl_periods;

SELECT * FROM dba_tables WHERE table_name LIKE 'GL%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 2. AP tables
--------------------------------------------------------------------------------
SELECT * FROM ap_invoices_all;
SELECT * FROM ap_invoice_lines_all;
SELECT * FROM ap_invoice_distributions_all;
SELECT * FROM ap_invoices_interface;
SELECT * FROM ap_invoice_lines_interface;

SELECT * FROM ap_suppliers;
SELECT * FROM ap_supplier_sites_all;
SELECT * FROM ap_suppliers_int;
SELECT * FROM ap_supplier_sites_int;

SELECT * FROM ap_checks_all;

SELECT * FROM dba_tables WHERE table_name LIKE 'AP%' OR owner = 'AP' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 3. AR tables
--------------------------------------------------------------------------------
SELECT * FROM ar_batches_all;
SELECT * FROM ar_periods;
SELECT * FROM ra_batches_all;

SELECT * FROM ra_customer_trx_all;
SELECT * FROM ra_customer_trx_lines_all;

SELECT * FROM ra_interface_lines_all;
SELECT * FROM ra_interface_errors_all;

SELECT * FROM dba_tables WHERE table_name LIKE 'AR%' OR table_name LIKE 'RA%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 4. PO tables
--------------------------------------------------------------------------------
SELECT * FROM po_headers_all;
SELECT * FROM po_lines_all;

SELECT * FROM po_headers_interface;
SELECT * FROM po_lines_interface;

SELECT * FROM po_requisition_headers_all;
SELECT * FROM po_requisition_lines_all;

SELECT * FROM dba_tables WHERE table_name LIKE 'PO%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 5. HR tables (PER/PAY)
--------------------------------------------------------------------------------
SELECT * FROM per_all_people_f;
SELECT * FROM per_all_assignments_f;
SELECT * FROM per_all_positions;
SELECT * FROM per_jobs;

SELECT * FROM hr_operating_units;
SELECT * FROM hr_all_organization_units;
SELECT * FROM hr_locations_all;

SELECT * FROM dba_tables WHERE table_name LIKE 'HR%' OR table_name LIKE 'PER%' OR table_name LIKE 'PAY%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 6. CE tables
--------------------------------------------------------------------------------
SELECT * FROM ce_bank_acct_uses_all;

SELECT * FROM ce_statement_headers;
SELECT * FROM ce_statement_lines;

SELECT * FROM ce_statement_headers_int;
SELECT * FROM ce_statement_lines_interface;

SELECT * FROM dba_tables WHERE table_name LIKE 'CE%' OR owner = 'CE' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 7. INV tables (MTL)
--------------------------------------------------------------------------------
SELECT * FROM mtl_system_items_b;
SELECT * FROM mtl_material_transactions;

SELECT * FROM dba_tables WHERE table_name LIKE 'INV%' OR owner = 'INV' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 8. FA tables
--------------------------------------------------------------------------------
SELECT * FROM fa_additions_b;
SELECT * FROM fa_additions_tl;

SELECT * FROM dba_tables WHERE table_name LIKE 'FA%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 9. ICX tables
--------------------------------------------------------------------------------
SELECT * FROM icx_sessions;
SELECT * FROM icx_parameters;
SELECT * FROM icx_transactions;

SELECT * FROM dba_tables WHERE table_name LIKE 'ICX%' OR owner = 'ICX' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 10. OE tables
--------------------------------------------------------------------------------
SELECT * FROM oe_order_headers_all;
SELECT * FROM oe_order_lines_all;

SELECT * FROM oe_headers_iface_all;
SELECT * FROM oe_lines_iface_all;

SELECT * FROM dba_tables WHERE table_name LIKE 'OE%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 11. XDO tables
--------------------------------------------------------------------------------
SELECT * FROM xdo_ds_definitions_b;
SELECT * FROM xdo_ds_definitions_tl;

SELECT * FROM xdo_templates_b;
SELECT * FROM xdo_templates_tl;

SELECT * FROM dba_tables WHERE table_name LIKE 'XDO%' OR owner = 'XDO' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 12. HZ tables
--------------------------------------------------------------------------------
SELECT * FROM hz_parties;
SELECT * FROM hz_party_sites;
SELECT * FROM hz_relationships;
SELECT * FROM hz_cust_accounts;
SELECT * FROM hz_cust_acct_sites_all;
SELECT * FROM hz_cust_site_uses_all;
SELECT * FROM hz_contact_points;
SELECT * FROM hz_locations;

SELECT * FROM dba_tables WHERE table_name LIKE 'HZ%' OR owner = 'HZ' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 13. FND tables
--------------------------------------------------------------------------------
SELECT * FROM fnd_user;
SELECT * FROM fnd_responsibility;
SELECT * FROM fnd_responsibility_tl;
SELECT * FROM fnd_application;
SELECT * FROM fnd_application_tl;
SELECT * FROM fnd_concurrent_programs;
SELECT * FROM fnd_concurrent_programs_tl;
SELECT * FROM fnd_lookup_values;
SELECT * FROM fnd_product_groups;
SELECT * FROM fnd_product_installations;
SELECT * FROM fnd_languages;

SELECT * FROM fnd_request_groups;
SELECT * FROM fnd_request_group_units;

SELECT * FROM dba_tables WHERE table_name LIKE 'FND%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 14. AD tables
--------------------------------------------------------------------------------
SELECT * FROM ad_applied_patches;
SELECT * FROM ad_bugs;
SELECT * FROM ad_trackable_entities ORDER BY 1;

SELECT * FROM dba_tables WHERE table_name LIKE 'AD%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 15. DBA tables
--------------------------------------------------------------------------------
SELECT * FROM dba_tables;
SELECT * FROM dba_tab_cols;
SELECT * FROM dba_views;
SELECT * FROM dba_source;
SELECT * FROM dba_tablespaces;
SELECT * FROM dba_data_files;
SELECT * FROM dba_temp_files;
SELECT * FROM dba_free_space;
SELECT * FROM dba_datapump_jobs;
SELECT * FROM dba_datapump_sessions;
SELECT * FROM dba_directories;
SELECT * FROM dba_jobs;
SELECT * FROM dba_log_groups;
SELECT * FROM dba_objects;
SELECT * FROM dba_pdbs;
SELECT * FROM DBA_RECYCLEBIN;
SELECT * FROM dba_roles;
SELECT * FROM dba_role_privs;
SELECT * FROM dba_rollback_segs;
SELECT * FROM dba_sequences;
SELECT * FROM dba_source;
SELECT * FROM dba_undo_extents;

SELECT * FROM dba_views WHERE view_name LIKE 'DBA%' ORDER BY 1, 2, 3;

--------------------------------------------------------------------------------
-- 15. WF tables
--------------------------------------------------------------------------------
SELECT * FROM dba_tables WHERE table_name LIKE 'WF%' ORDER BY 1, 2, 3;
SELECT * FROM WF_NOTIFICATIONS;
SELECT * FROM WF_DEFERRED;

--------------------------------------------------------------------------------
SELECT * FROM dba_objects WHERE object_name LIKE '%OPERATING%' AND object_type IN ('TABLE', 'VIEW');
--------------------------------------------------------------------------------
SELECT sys_context('USERENV', 'DB_NAME') db_name FROM dual;
--------------------------------------------------------------------------------
