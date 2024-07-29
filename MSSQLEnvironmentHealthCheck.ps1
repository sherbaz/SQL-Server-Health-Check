Import-Module SQLPS -DisableNameChecking

$outputFilePath = "HealthCheck_"+(Get-Date).DayOfYear+".html"

$htmlBody = $null

$htmlBody += "<div style=""background:#666; padding:1px;""><div style=""background:#AAA; color:#333; overflow:hidden; text-align:center; padding:5px;"">
                <b><span style=""color:#000; font-weight:strong;"">www.Sherbaz.com</span></b>
                | MSSQL Health Report: "+ (Get-Date) +"</div></div><br />"

#=== Root Blockers
$htmlBody += "
        <b>Root Blockers(if any)</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>ServerName</th><th>EventTime</th><th>loginame</th><th>spid</th>
                    <th>blocked</th><th>lastwaittype</th><th>login_time</th>
                    <th>last_batch</th><th>Status</th><th>hostname</th>
                    <th>program_name</th><th>hostprocess</th>
                    </tr>"

$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "select getdate() as EventTime,loginame,spid,blocked,lastwaittype,
            login_time,last_batch,[status],hostname,[program_name],hostprocess
            from  master..sysprocesses a where  exists ( select b.* from master..sysprocesses b where b.blocked > 0 and b.blocked = a.spid ) and not
            exists ( select b.* from master..sysprocesses b where b.blocked > 0 and b.spid = a.spid ) 
            order by spid;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.EventTime+"</td><td>"+$record.loginame+"</td>
                        <td>"+$record.spid+"</td><td>"+$record.blocked+"</td><td>"+$record.lastwaittype+"</td>
                        <td>"+$record.login_time+"</td><td>"+$record.last_batch+"</td><td>"+$record.status+"</td>
                        <td>"+$record.hostname+"</td><td>"+$record.program_name+"</td><td>"+$record.hostprocess+"</td>
                        </tr>"
    }
}

$htmlBody += "</table><br />"

#=== Blocking Tree
$htmlBody += "
        <b>Blocking Tree</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>ServerName</th><th>EventTime</th><th>BLOCKING_TREE</th>
                    </tr>"

$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "SELECT SPID, BLOCKED, REPLACE (REPLACE (T.TEXT, CHAR(10), ' '), CHAR (13), ' ' ) AS BATCH
                INTO #T
                FROM sys.sysprocesses R CROSS APPLY sys.dm_exec_sql_text(R.SQL_HANDLE) T;                
                WITH BLOCKERS (SPID, BLOCKED, LEVEL, BATCH)
                AS
                (
                SELECT SPID,
                BLOCKED,
                CAST (REPLICATE ('0', 4-LEN (CAST (SPID AS VARCHAR))) + CAST (SPID AS VARCHAR) AS VARCHAR (1000)) AS LEVEL,
                BATCH FROM #T R
                WHERE (BLOCKED = 0 OR BLOCKED = SPID)
                AND EXISTS (SELECT * FROM #T R2 WHERE R2.BLOCKED = R.SPID AND R2.BLOCKED <> R2.SPID)
                UNION ALL
                SELECT R.SPID,
                R.BLOCKED,
                CAST (BLOCKERS.LEVEL + RIGHT (CAST ((1000 + R.SPID) AS VARCHAR (100)), 4) AS VARCHAR (1000)) AS LEVEL,
                R.BATCH FROM #T AS R
                INNER JOIN BLOCKERS ON R.BLOCKED = BLOCKERS.SPID WHERE R.BLOCKED > 0 AND R.BLOCKED <> R.SPID
                )
                SELECT getdate() as EventTime, N'    ' + REPLICATE (N'|         ', LEN (LEVEL)/4 - 1) +
                CASE WHEN (LEN(LEVEL)/4 - 1) = 0
                THEN 'HEAD -  '
                ELSE '|------  ' END
                + CAST (SPID AS NVARCHAR (10)) + N' ' + BATCH AS BLOCKING_TREE
                FROM BLOCKERS ORDER BY LEVEL ASC;
                DROP TABLE #T;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.EventTime+"</td><td>"+$record.BLOCKING_TREE+"</td>
                      </tr>"
    }
}

$htmlBody += "</table><br />"

#=== Memory Utilization
$htmlBody += "
        <b>Memory Usage</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>SQLServerStartTime</th><th>SQLCurrentMemoryUsage(MB)</th>
                    <th>SQLMaxMemoryTarget(MB)</th><th>OSTotalMemory(MB)</th><th>OSAvailableMemory(MB)</th></tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
        SELECT 
            sqlserver_start_time AS [SQLServerStartTime],
            (committed_kb / 1024) AS [SQLCurrentMemoryUsage],
            (committed_target_kb / 1024) AS [SQLMaxMemoryTarget],
            (total_physical_memory_kb / 1024) AS [OSTotalMemory],
            (available_physical_memory_kb / 1024) AS [OSAvailableMemory]
        FROM 
            sys.dm_os_sys_info
        CROSS JOIN 
            sys.dm_os_sys_memory;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.SQLServerStartTime+"</td><td>"+$record.SQLCurrentMemoryUsage+"</td>
                        <td>"+$record.SQLMaxMemoryTarget+"</td><td>"+$record.OSTotalMemory+"</td><td>"+$record.OSAvailableMemory+"</td></tr>"
    }
}

$htmlBody += "</table><br />"

#=== CPU Utilization
$htmlBody += "
        <b>CPU Usage</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>SQLServer_CPU</th><th>System_Idle_Process</th>
                    <th>Other_Process_CPU</th><th>EventTime</th></tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
        DECLARE @ts BIGINT;
        DECLARE @lastNmin TINYINT;
        SET @lastNmin = 200;
        SELECT @ts =(SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info); 
        SELECT TOP(@lastNmin)
                @@servername as ServerName,
		        SQLProcessUtilization AS [SQLServer_CPU_Utilization],
		        SystemIdle AS [System_Idle_Process], 
		        100 - SystemIdle - SQLProcessUtilization AS [Other_Process_CPU_Utilization], 
		        DATEADD(ms,-1 *(@ts - [timestamp]),GETDATE())AS [Event_Time] 
        FROM (SELECT record.value('(./Record/@id)[1]','int')AS record_id, 
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')AS [SystemIdle], 
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')AS [SQLProcessUtilization], 
        [timestamp]      
        FROM (SELECT[timestamp], convert(xml, record) AS [record]             
        FROM sys.dm_os_ring_buffers             
        WHERE ring_buffer_type =N'RING_BUFFER_SCHEDULER_MONITOR'AND record LIKE'%%')AS x )AS y
        where SystemIdle < 50
        ORDER BY record_id DESC;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.SQLServer_CPU_Utilization+"</td><td>"+$record.System_Idle_Process+"</td>
                        <td>"+$record.Other_Process_CPU_Utilization+"</td><td>"+$record.Event_Time+"</td></tr>"
    }
}

$htmlBody += "</table><br />"

#=== Backup Status
$htmlBody += "
        <b>Backup Status</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>Database</th><th>LastFullBackup</th>
                    <th>LastLogBackup</th></tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
        WITH LastFullBackup AS (
            SELECT database_name, 
                   MAX(backup_finish_date) AS LastFullBackupDate
            FROM msdb.dbo.backupset
            WHERE type = 'D'
            GROUP BY database_name
        ),
        LastLogBackup AS (
            SELECT database_name, 
                   MAX(backup_finish_date) AS LastLogBackupDate
            FROM msdb.dbo.backupset
            WHERE type = 'L'
            GROUP BY database_name
        )
        SELECT @@servername as ServerName, d.name AS DatabaseName, 
               ISNULL(CONVERT(VARCHAR, f.LastFullBackupDate, 120), 'NEVER') AS LastFullBackup,
               ISNULL(CONVERT(VARCHAR, l.LastLogBackupDate, 120), 'NEVER') AS LastLogBackup
        FROM sys.databases d
        LEFT JOIN LastFullBackup f ON d.name = f.database_name
        LEFT JOIN LastLogBackup l ON d.name = l.database_name
        ORDER BY d.name;
" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.DatabaseName+"</td><td>"+$record.LastFullBackup+"</td>
                        <td>"+$record.LastLogBackup+"</td></tr>"
    }
}

$htmlBody += "</table><br />"

#=== Drive Space
$htmlBody += "
        <b>Drive Space &lt; 30%</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>Drive</th><th>FreeSpaceInGB</th>
                    <th>TotalSpaceInGB</th><th>FreeSpaceInPct</th><th>EventTime</th></tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
        SELECT DISTINCT dovs.volume_mount_point AS Drive,
        CONVERT(decimal,dovs.available_bytes/1048576/1024) AS FreeSpaceInGB,
        convert(decimal,dovs.total_bytes/1048576/1024) as TotalSpaceInGB,
        cast(CONVERT(decimal,dovs.available_bytes/1048576/1024)/convert(decimal,dovs.total_bytes/1048576/1024)*100 as decimal(38,2)) as FreeSpaceInPct,
        getdate() as EventTime
        --into #diskspace
        FROM sys.master_files mf
        CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.FILE_ID) dovs
        where cast(CONVERT(decimal,dovs.available_bytes/1048576/1024)/convert(decimal,dovs.total_bytes/1048576/1024)*100 as decimal(38,2)) < 60
        ORDER BY FreeSpaceInGB ASC;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.Drive+"</td><td>"+$record.FreeSpaceInGB+"</td>
           <td>"+$record.TotalSpaceInGB+"</td><td>"+$record.FreeSpaceInPct+"</td><td>"+$record.EventTime+"</td></tr>"
    }
}

$htmlBody += "</table><br />"

#=== SQL Server Agent Job Status
$htmlBody += "
        <b>SQL Server Agent Job Status</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>JobName</th><th>TimeRun</th>
                    <th>JobStatus</th><th>JobOutcome</th></tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
                    USE MSDB
                    GO

                    WITH CTE_MostRecentJobRun AS (
                        SELECT 
                            job_id,
                            run_status,
                            run_date,
                            run_time,
                            ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
                        FROM sysjobhistory
                        WHERE step_id = 0
                    )
                    SELECT 
                        j.name AS [JobName],
                        CASE 
                            WHEN j.enabled = 1 THEN 'Enabled' 
                            ELSE 'Disabled' 
                        END AS [JobStatus],
                        CASE 
                            WHEN mr.run_status = 0 THEN 'Failed'
                            WHEN mr.run_status = 1 THEN 'Succeeded'
                            WHEN mr.run_status = 2 THEN 'Retry'
                            WHEN mr.run_status = 3 THEN 'Cancelled'
                            ELSE 'Unknown'
                        END AS [JobOutcome],
                        CONVERT(VARCHAR, DATEADD(S, (mr.run_time/10000)*60*60 + ((mr.run_time - (mr.run_time/10000) * 10000)/100) * 60 + (mr.run_time - (mr.run_time/100) * 100), CONVERT(DATETIME, RTRIM(mr.run_date), 113)), 100) AS [LastRunTime]
                    FROM sysjobs j
                    JOIN CTE_MostRecentJobRun mr ON j.job_id = mr.job_id
                    WHERE mr.rn = 1
                    ORDER BY j.name;

            " -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.JobName+"</td><td>"+$record.TimeRun+"</td>
           <td>"+$record.JobStatus+"</td><td>"+$record.JobOutcome+"</td></tr>"
    }
}

$htmlBody += "</table><br />"


#=== Error logs
$htmlBody += "
        <b>Errorlog</b>
        <table style=""border:1px dotted black; font-size:small; background: #EEE;"">
                <tr style=""background:#000080; color:#FFF; border:1px solid black;"">
                    <th>Servername</th><th>LogDate</th><th>Text</th>
                    </tr>"
$results = $null
foreach($instance in Get-Content serverlist.txt) {
    $results += Invoke-Sqlcmd -Query "
                    /* 
                    script name: ErrorLogs.sql 
                    Runs xp_readerrorlog to query the errorlog for entries for the past x amount of days. 
                    */ 
  
                    SET NOCOUNT ON 
  
                    -- cleanup temp tables in case they were left behind 
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE table_name = '#servername') DROP TABLE #servername 
                    IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE table_name = '#xp_readerrorlog') DROP TABLE #xp_readerrorlog 
  
                    -- declare and set variables 
                    DECLARE @NumOfLogDays INT 
                    DECLARE @startdate DATETIME 
                    DECLARE @enddate DATETIME 
  
                    IF (SELECT DATENAME(WEEKDAY, GETDATE())) like 'Monday' SET @NumOfLogDays = 3 ELSE SET @NumOfLogDays = 1 -- if it's Monday get 3 days of jobs 
                    SET @startdate=GETDATE() - @NumOfLogDays 
                    SET @enddate=GETDATE() 
  
                    -- create and populate temp tables 
                    CREATE TABLE #servername (ServerName VARCHAR(100)) 
                    INSERT INTO #servername 
                    SELECT @@servername 
  
                    CREATE TABLE #xp_readerrorlog(LogDate varchar(30),ProcessInfo varchar(30),Text varchar(max)) 
                    INSERT INTO #xp_readerrorlog 
                    EXEC xp_readerrorlog 0,1,NULL,NULL,@startdate,@enddate,'asc' 
  
                    -- join temp tables 
                    SELECT a.ServerName, b.LogDate, b.Text as 'Text' 
                    FROM #servername a, #xp_readerrorlog b;" -ServerInstance $instance

    foreach($record in $results)
    {
        $htmlBody += "<tr><td>"+$instance+"</td><td>"+$record.LogDate+"</td><td>"+$record.Text+"</td></tr>"
    }
}

$htmlBody += "</table><br />"

ConvertTo-HTML -head "<head><title>Healthcheck</title></head>" -body $htmlbody | out-file -FilePath $outputFilePath
