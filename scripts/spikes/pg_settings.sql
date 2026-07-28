\pset pager off

SELECT name, setting, reset_val
FROM pg_settings
WHERE name IN ('role', 'session_authorization')
ORDER BY name;

SELECT current_setting('role') AS role,
       current_setting('session_authorization') AS session_authorization;

SET application_name = 'guard_spike';
SELECT name, setting, reset_val
FROM pg_settings
WHERE name = 'application_name';
RESET application_name;

SET myapp.tenant_id = '42';
SELECT current_setting('myapp.tenant_id', true) AS custom_setting;
RESET myapp.tenant_id;
SELECT current_setting('myapp.tenant_id', true) AS custom_after_reset;
