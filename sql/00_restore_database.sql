-- =============================================
-- 00_restore_database.sql
-- Restore AdventureWorksDW2022 on SQL Server 2025 Express
-- =============================================
USE master;
GO

RESTORE DATABASE AdventureWorksDW2022
FROM DISK = N'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\AdventureWorksDW2022.bak'
WITH
    MOVE N'AdventureWorksDW2022'     TO N'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\AdventureWorksDW2022.mdf',
    MOVE N'AdventureWorksDW2022_log' TO N'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\AdventureWorksDW2022_log.ldf',
    RECOVERY,
    STATS = 10;
GO

-- Verify
USE AdventureWorksDW2022;
GO
SELECT COUNT(*) AS FinanceRows FROM dbo.FactFinance;
GO
