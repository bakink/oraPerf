
set termout on
PROMPT
PROMPT &_C_YELLOW Diaplay lowest sample time in v$active_session_history &_C_RESET
PROMPT

SELECT MIN(sample_time) AS min_sample_time
FROM   v$active_session_history;


@@rtdiag_4