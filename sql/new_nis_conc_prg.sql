--------------------------------------------------------------------------------
-- new_nis_conc_prg.sql
--------------------------------------------------------------------------------
-- Sets up XX_NEW_NIS concurrent program on new instance
-- Remember to manually upload the XX_NEW_NIS template
--------------------------------------------------------------------------------
-- Ver Date       Author   Change
-- 1   01-FEB-19  vseeram  Created
-- 2   07-MAY-19  vseeram  Changed filename, exiting messages
-------------------------------------------------------------------------------
SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE    
  c_old_conc_prog            VARCHAR2(8) := 'XX_NIS';
  c_new_conc_prog            VARCHAR2(12) := 'XX_NEW_NIS';
  c_application_short_name   VARCHAR2(3) := 'PAY';
  c_program_application      CONSTANT VARCHAR2 (200) := 'Payroll';
  c_request_group            CONSTANT VARCHAR2 (200) := 'Global SHRMS Reports & Process';
  c_group_application        CONSTANT VARCHAR2 (200) := 'Human Resources';

  lb_executable_exists       BOOLEAN := NULL;
  lb_program_exists          BOOLEAN := NULL;
  lb_parameter_exists        BOOLEAN := NULL;
  lb_xdo_data_defn_exists    BOOLEAN := FALSE;
  lb_xdo_template_exists     BOOLEAN := FALSE;
  lb_request_group_exists    BOOLEAN := FALSE;
  lv_dbname                  VARCHAR2(255);
  lv_flex_value_set_name     VARCHAR2(255);
  lv_data_source_code        VARCHAR2(255);
  ln_template_id             NUMBER;
  ln_request_unit_id         NUMBER;
  lv_rowid                   VARCHAR2(255);

  -- cursor to get database name
  CURSOR c_dbname IS
  SELECT
    name
  FROM
    v$database;

  -- cursor to get existing XX NIS report concurrent program definition
  CURSOR c_conc_prg_defn IS
  SELECT 
    *
  FROM
    fnd_concurrent_programs
  WHERE
    concurrent_program_name = c_old_conc_prog;
  v_conc_prg_defn fnd_concurrent_programs%rowtype;


  -- cursor for concurrent program parameters
  CURSOR c_conc_param_defn IS
  SELECT
    *
  FROM
    fnd_descr_flex_col_usage_vl
  WHERE
    descriptive_flexfield_name = '$SRS$.' || c_old_conc_prog;
  v_conc_param_defn fnd_descr_flex_col_usage_vl%rowtype;


  -- 
  CURSOR c_flex_value_set_name(p_flex_value_set_id NUMBER) IS
  SELECT
    flex_value_set_name
  FROM
    fnd_flex_value_sets
  WHERE
    flex_value_set_id = p_flex_value_set_id;


  -- check for XX_NEW_NIS XML Publisher data definition
  CURSOR c_data_source_code IS
  SELECT
    data_source_code 
  FROM
    xdo_ds_definitions_b
  WHERE
    data_source_code = c_new_conc_prog
  AND SYSDATE BETWEEN start_date AND NVL(end_date, TO_DATE('31-DEC-4712'))
  ;


  -- check for XX_NEW_NIS XML Publisher template
  CURSOR c_template_code(p_new_conc_prog VARCHAR2) IS
  SELECT
    template_id
  FROM
    xdo_templates_b
  WHERE
    template_code like p_new_conc_prog
  AND SYSDATE BETWEEN start_date AND NVL(end_date, TO_DATE('31-DEC-4712'))
  ORDER BY 
    template_id DESC;


  -- check for XX_NEW_NIS request group
  CURSOR request_group_cur IS
  SELECT
    request_unit_id
  FROM
    fnd_request_group_units
  WHERE
    request_unit_id IN (
      SELECT
        concurrent_program_id
      FROM
        fnd_concurrent_programs
      WHERE
        concurrent_program_name = c_new_conc_prog
    );

BEGIN
  OPEN c_dbname;
  FETCH c_dbname INTO lv_dbname;
  CLOSE c_dbname;
  dbms_output.put_line('Setting up ' || c_new_conc_prog || ' on ' || lv_dbname || '...');

  -------------------------------------------------------------------------------
  -- 1. Check if concurrent program executable exists
  -------------------------------------------------------------------------------
  lb_executable_exists := fnd_program.executable_exists(c_new_conc_prog, c_application_short_name);
  
  -------------------------------------------------------------------------------
  -- 2. If executable does not exist, create new concurrent program executable
  -------------------------------------------------------------------------------
  IF lb_executable_exists THEN
    dbms_output.put_line('Concurrent program executable "' || c_new_conc_prog || '" already exists');
  ELSE
    fnd_program.executable(executable => c_new_conc_prog, 
      application => c_application_short_name, 
      short_name => c_new_conc_prog,
      description => '',
      execution_method => 'Oracle Reports',
      execution_file_name => c_new_conc_prog
    );
    COMMIT;
    dbms_output.put_line('Concurrent program executable "' || c_new_conc_prog || '" created');
  END IF;

  -------------------------------------------------------------------------------
  -- 3. Check if concurrent program definition exists
  -------------------------------------------------------------------------------
  lb_program_exists := fnd_program.program_exists(c_new_conc_prog, c_application_short_name);

  -------------------------------------------------------------------------------
  -- 4. If definition does not exist, create new concurrent program definition
  -------------------------------------------------------------------------------
  IF lb_program_exists THEN
    dbms_output.put_line('Concurrent program definition "' || c_new_conc_prog || '" already exists');
  ELSE
    OPEN c_conc_prg_defn;
    FETCH c_conc_prg_defn INTO v_conc_prg_defn;
    CLOSE c_conc_prg_defn;
    fnd_program.register (
      program => c_new_conc_prog,
      application => c_application_short_name,
      enabled => 'Y',
      short_name => c_new_conc_prog,
      description => '',
      executable_short_name => c_new_conc_prog,
      executable_application => c_application_short_name,
      execution_options => null,
      priority => v_conc_prg_defn.request_priority,
      save_output => v_conc_prg_defn.save_output_flag,
      print => v_conc_prg_defn.print_flag,
      cols => v_conc_prg_defn.minimum_width,
      rows => v_conc_prg_defn.minimum_length,
      style => v_conc_prg_defn.output_print_style,
      style_required => v_conc_prg_defn.required_style,
      printer => v_conc_prg_defn.printer_name,
      request_type => null,
      request_type_application => null,
      use_in_srs => v_conc_prg_defn.srs_flag,
      allow_disabled_values => 'N',
      run_alone => 'N',
      output_type => v_conc_prg_defn.output_file_type,
      enable_trace => v_conc_prg_defn.enable_trace,
      restart => v_conc_prg_defn.restart,
      nls_compliant => v_conc_prg_defn.nls_compliant,
      icon_name => v_conc_prg_defn.icon_name,
      language_code => 'US',
      mls_function_short_name => null,
      mls_function_application => null,
      incrementor => null,
      refresh_portlet => null
    );
    COMMIT;
    dbms_output.put_line('Concurrent program definition "' || c_new_conc_prog || '" created');
  END IF;

  -------------------------------------------------------------------------------
  -- 5. Loop to begin checking for concurrent program parameters
  -------------------------------------------------------------------------------
  OPEN c_conc_param_defn;
  LOOP
    FETCH c_conc_param_defn INTO v_conc_param_defn;
    EXIT WHEN c_conc_param_defn%NOTFOUND;

  -------------------------------------------------------------------------------
  -- 6. Check if concurrent program parameters exists
  -------------------------------------------------------------------------------
    lb_parameter_exists := NULL;
    lb_parameter_exists := fnd_program.parameter_exists(c_new_conc_prog, c_application_short_name, v_conc_param_defn.end_user_column_name);
    IF lb_parameter_exists THEN
      dbms_output.put_line('Concurrent program parameter "' || v_conc_param_defn.end_user_column_name || '" already exists in ' || c_new_conc_prog);
    ELSE
      OPEN c_flex_value_set_name(v_conc_param_defn.flex_value_set_id);
      FETCH c_flex_value_set_name INTO lv_flex_value_set_name;
      CLOSE c_flex_value_set_name;
      fnd_program.parameter(program_short_name => c_new_conc_prog,
        application => c_application_short_name,
        sequence => v_conc_param_defn.column_seq_num,
        parameter => v_conc_param_defn.end_user_column_name,
        description => v_conc_param_defn.description,
        enabled => v_conc_param_defn.enabled_flag,
        value_set => lv_flex_value_set_name,
        default_type => v_conc_param_defn.default_type,
        default_value => v_conc_param_defn.default_value,
        required => v_conc_param_defn.required_flag,
        enable_security => v_conc_param_defn.security_enabled_flag,
        range => v_conc_param_defn.range_code,
        display => v_conc_param_defn.display_flag,
        display_size => v_conc_param_defn.display_size,
        description_size => v_conc_param_defn.maximum_description_len,
        concatenated_description_size => v_conc_param_defn.concatenation_description_len,
        prompt => v_conc_param_defn.form_left_prompt,
        token => v_conc_param_defn.srw_param,
        cd_parameter => 'N'
      );
      COMMIT;
      dbms_output.put_line('Concurrent program parameter "' || v_conc_param_defn.end_user_column_name || '" created in ' || c_new_conc_prog);
    END IF; 
  END LOOP;  
  CLOSE c_conc_param_defn;

  -------------------------------------------------------------------------------
  -- 7. Create XML Publisher data definition
  -------------------------------------------------------------------------------
  OPEN c_data_source_code;
  FETCH c_data_source_code INTO lv_data_source_code;
  CLOSE c_data_source_code;
  
  lb_xdo_data_defn_exists := (lv_data_source_code IS NOT NULL);  
  IF lb_xdo_data_defn_exists = TRUE THEN
    dbms_output.put_line('XML Data Definition "' || c_new_conc_prog || '" already exists');
  ELSE  
    xdo_ds_definitions_pkg.insert_row (
      x_rowid                  => lv_rowid,
      x_application_short_name => c_application_short_name,
      x_data_source_code       => c_new_conc_prog,
      x_data_source_status     => 'E',
      x_start_date             => TRUNC(sysdate),
      x_end_date               => NULL,
      x_object_version_number  => 1,
      x_attribute_category     => NULL,
      x_attribute1             => NULL,
      x_attribute2             => NULL,
      x_attribute3             => NULL,
      x_attribute4             => NULL,
      x_attribute5             => NULL,
      x_attribute6             => NULL,
      x_attribute7             => NULL,
      x_attribute8             => NULL,
      x_attribute9             => NULL,
      x_attribute10            => NULL,
      x_attribute11            => NULL,
      x_attribute12            => NULL,
      x_attribute13            => NULL,
      x_attribute14            => NULL,
      x_attribute15            => NULL,
      x_data_source_name       => c_new_conc_prog,
      x_description            => '',
      x_creation_date          => TRUNC(sysdate),
      x_created_by             => 0,
      x_last_update_date       => TRUNC(sysdate),
      x_last_updated_by        => 0,
      x_last_update_login      => 0
    );
    COMMIT;
    dbms_output.put_line('XML data definition "' || c_new_conc_prog || '" created');
  END IF;


  -------------------------------------------------------------------------------
  -- 7. Create XML Publisher template
  -------------------------------------------------------------------------------
  OPEN c_template_code(c_new_conc_prog);
  FETCH c_template_code INTO ln_template_id;
  CLOSE c_template_code;

  lb_xdo_template_exists := (ln_template_id IS NOT NULL);  
  IF lb_xdo_template_exists = TRUE THEN
    dbms_output.put_line('XML Template "' || c_new_conc_prog || '" already exists');
  ELSE  
    SELECT
      MAX(template_id)
    INTO
      ln_template_id
    FROM
      xdo_templates_b;
    xdo_templates_pkg.insert_row (x_rowid => lv_rowid,
      x_application_short_name => c_application_short_name,
      x_template_code => c_new_conc_prog,
      x_template_id => ln_template_id + 1,
      x_application_id => 801,
      x_ds_app_short_name => c_application_short_name,
      x_data_source_code => c_new_conc_prog,
      x_template_type_code => 'RTF',
      x_default_language => 'en',
      x_default_territory => '00',
      x_default_output_type => 'EXCEL',
      x_mls_language => NULL,
      x_mls_territory => NULL,
      x_template_status => 'E',
      x_use_alias_table => 'N',
      x_start_date => TRUNC(sysdate),
      x_end_date => NULL,
      x_dependency_flag => 'P',
      x_object_version_number => 0,
      x_attribute_category     => NULL,
      x_attribute1             => NULL,
      x_attribute2             => NULL,
      x_attribute3             => NULL,
      x_attribute4             => NULL,
      x_attribute5             => NULL,
      x_attribute6             => NULL,
      x_attribute7             => NULL,
      x_attribute8             => NULL,
      x_attribute9             => NULL,
      x_attribute10            => NULL,
      x_attribute11            => NULL,
      x_attribute12            => NULL,
      x_attribute13            => NULL,
      x_attribute14            => NULL,
      x_attribute15            => NULL,
      x_template_name          => c_new_conc_prog,
      x_description            => '',
      x_creation_date          => TRUNC(sysdate),
      x_created_by             => 0,
      x_last_update_date       => TRUNC(sysdate),
      x_last_updated_by        => 0,
      x_last_update_login      => 0
    );
    COMMIT;
    dbms_output.put_line('XML template "' || c_new_conc_prog || ' created');
  END IF;
  
  -------------------------------------------------------------------------------
  -- 8. Add concurrent program to request group
  -------------------------------------------------------------------------------
  OPEN request_group_cur;
  FETCH request_group_cur INTO ln_request_unit_id;
  CLOSE request_group_cur;
  
  lb_request_group_exists := (ln_request_unit_id IS NOT NULL);  
  IF lb_request_group_exists = TRUE THEN
    dbms_output.put_line('Concurrent program "' || c_new_conc_prog || '" already exists in request group "' || c_request_group || '"');
  ELSE
    apps.fnd_program.add_to_group (program_short_name  => c_new_conc_prog,
      program_application => c_program_application,
      request_group       => c_request_group,
      group_application   => c_group_application
    );
    COMMIT;
    dbms_output.put_line('Concurrent program "' || c_new_conc_prog || '" added to request group "' || c_request_group || '"');
  END IF;
  
  dbms_output.put_line('');
  dbms_output.put_line('All done!');
  dbms_output.put_line('Remember to:');
  dbms_output.put_line('1. Update RTF template for ' || c_new_conc_prog || ' using XML Publisher Administrator responsibility');
  dbms_output.put_line('2. Upload ' || c_new_conc_prog || '.rdf to $PAY_TOP/reports/US directory onto server');
  dbms_output.put_line('3. Log off EBS and log back on after making above changes');  
  dbms_output.put_line('n.b. If the XX_NEW_NIS concurrent program completes with warning, check the log and see if the temp directory exists on the server');
EXCEPTION
  WHEN OTHERS THEN
   dbms_output.put_line('Error occurred: ' || SQLCODE || ' - ' || SQLERRM);
END;
/

