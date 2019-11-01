# SQL-Server-Health-Check
Its always good to know that your Database environment is healthy before your start your day or before the business load rips through your SQL Server Database Farm. Hence, here is a miniature script to Connect to all SQL Server instances in an environment to do a daily morning healthcheck and generate an HTML report.

My initial script had workflows to define, sql logins, authentication, windows/SQL, IP address / DNS name etc. Also I had several key healthchecks defined including Backup status, patch level, Replication status, AAG status, SQL Agent job status(24 hours), Errors from SQL errorlogs/traces etc. I lost the script to some theives. I am now rebuilding all in a better way from scratch on GitHub.

Add all SQL instance names into a serverlist.txt file and run the script from the same folder.

References:
1. Pinal Dave's Blog
2. MSDN
