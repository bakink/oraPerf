REM ***** based on http://datavirtualizer.com/oracle-cpu-time/
REM ***** There are 3 kinds of CPU in the Oracle stats.
REM *****   System CPU used
REM *****   Oracle CPU used
REM *****   Oracle demand for CPU
REM ***** the amount of time “On CPU” from ASH subtract the amount of CPU in Oracle statistics for CPU usage,
REM ***** the remainder is ROUGHLY the time spent by Oracle sessions waiting to get onto the CPU.

with CPU_WAIT_STAT as (
           select
                 decode(n.wait_class,'User I/O','User I/O',
                                     'Commit','Commit',
                                     'Wait') CLASS,
                 sum(round(m.time_waited/m.INTSIZE_CSEC,3)) METRICVALUE,
                 BEGIN_TIME ,
                 END_TIME
           from  v$waitclassmetric  m,
                 v$system_wait_class n
           where m.wait_class_id=n.wait_class_id
             and n.wait_class != 'Idle'
           group by  decode(n.wait_class,'User I/O','User I/O', 'Commit','Commit', 'Wait'), BEGIN_TIME, END_TIME
          union
             select 'CPU_ORA_CONSUMED' CLASS,
                 value/100 METRICVALUE,
                 BEGIN_TIME ,
                 END_TIME
             from v$sysmetric
             where metric_name='CPU Usage Per Sec'
               and group_id=(SELECT group_id FROM v$metricgroup WHERE name = 'System Metrics Long Duration')
          union
            select 'CPU_HOST' CLASS ,
                 value/100 METRICVALUE,
                 BEGIN_TIME ,
                 END_TIME
            from v$sysmetric 
            where metric_name='Host CPU Usage Per Sec' and group_id=(SELECT group_id FROM v$metricgroup WHERE name = 'System Metrics Long Duration')
          union
             select
               'CPU_ORA_DEMAND' CLASS,
               nvl(round( sum(decode(session_state,'ON CPU',1,0))/60,2),0) METRICVALUE,
               cast(min(SAMPLE_TIME) as date) BEGIN_TIME ,
               cast(max(SAMPLE_TIME) as date) END_TIME
             from v$active_session_history ash,
             (select begin_time, end_time from v$metric where metric_name='Host CPU Usage Per Sec' and group_id=(SELECT group_id FROM v$metricgroup WHERE name = 'System Metrics Long Duration')) timerange
             where SAMPLE_TIME between timerange.begin_time and timerange.end_time
)
select
       to_char(BEGIN_TIME,'HH:MI:SS') BEGIN_TIME,
       to_char(END_TIME,'HH:MI:SS') END_TIME,
       (SELECT value FROM v$osstat WHERE stat_name = 'NUM_CPUS') AS num_cpus,
       (SELECT value FROM v$osstat WHERE stat_name = 'NUM_CPU_CORES') AS num_cpu_cores,
       CPU_HOST,
       decode(sign(CPU_HOST-CPU_ORA_CONSUMED), -1, 0, (CPU_HOST - CPU_ORA_CONSUMED )) CPU_OS,
       CPU_ORA_CONSUMED CPU_ORA,
       decode(sign(CPU_ORA_DEMAND-CPU_ORA_CONSUMED), -1, 0, (CPU_ORA_DEMAND - CPU_ORA_CONSUMED )) CPU_ORA_WAIT,
       COMMIT,
       READIO,
       WAIT 
from ( 
        select 
                min(BEGIN_TIME) BEGIN_TIME,
                max(END_TIME) END_TIME, 
                sum(decode(CLASS,'CPU_ORA_CONSUMED',METRICVALUE,0)) CPU_ORA_CONSUMED, 
                sum(decode(CLASS,'CPU_ORA_DEMAND' ,METRICVALUE,0)) CPU_ORA_DEMAND, 
                sum(decode(CLASS,'CPU_HOST' ,METRICVALUE,0)) CPU_HOST, 
                sum(decode(CLASS,'Commit' ,METRICVALUE,0)) COMMIT, 
                sum(decode(CLASS,'User I/O' ,METRICVALUE,0)) READIO, 
                sum(decode(CLASS,'Wait' ,METRICVALUE,0)) WAIT               
         from CPU_WAIT_STAT) 
/