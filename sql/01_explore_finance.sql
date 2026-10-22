-- =============================================
-- 01_explore_finance.sql
-- Step 1.1: Explore FactFinance and its dimensions
-- Run each block separately (select it, then Ctrl+Shift+E)
-- =============================================
USE AdventureWorksDW2022;
GO

-- (A) Row count of each table in the finance model
SELECT 'FactFinance'        AS TableName, COUNT(*) AS Rows FROM dbo.FactFinance        UNION ALL
SELECT 'DimAccount',                      COUNT(*)         FROM dbo.DimAccount         UNION ALL
SELECT 'DimScenario',                     COUNT(*)         FROM dbo.DimScenario        UNION ALL
SELECT 'DimDepartmentGroup',              COUNT(*)         FROM dbo.DimDepartmentGroup UNION ALL
SELECT 'DimOrganization',                 COUNT(*)         FROM dbo.DimOrganization;

-- (B) Rows and amount per scenario (Actual / Budget / Forecast)
SELECT  s.ScenarioName,
        COUNT(*)            AS Rows,
        SUM(f.Amount)       AS TotalAmount   -- raw sum, NOT a real total (signs ignored)
FROM    dbo.FactFinance f
JOIN    dbo.DimScenario s ON s.ScenarioKey = f.ScenarioKey
GROUP BY s.ScenarioName
ORDER BY s.ScenarioName;

-- (C) Which years/months exist for each scenario?
SELECT  s.ScenarioName,
        d.CalendarYear,
        COUNT(DISTINCT d.MonthNumberOfYear) AS Months,
        COUNT(*)                            AS Rows
FROM    dbo.FactFinance f
JOIN    dbo.DimScenario s ON s.ScenarioKey = f.ScenarioKey
JOIN    dbo.DimDate     d ON d.DateKey     = f.DateKey
GROUP BY s.ScenarioName, d.CalendarYear
ORDER BY d.CalendarYear, s.ScenarioName;

-- (D) Organizations (branches) and their currencies
SELECT  o.OrganizationKey,
        o.OrganizationName,
        o.ParentOrganizationKey,
        c.CurrencyName,
        COUNT(f.OrganizationKey) AS FactRows
FROM    dbo.DimOrganization o
LEFT JOIN dbo.DimCurrency c ON c.CurrencyKey     = o.CurrencyKey
LEFT JOIN dbo.FactFinance f ON f.OrganizationKey = o.OrganizationKey
GROUP BY o.OrganizationKey, o.OrganizationName, o.ParentOrganizationKey, c.CurrencyName
ORDER BY o.OrganizationKey;

-- (E) Departments
SELECT  DepartmentGroupKey, DepartmentGroupName, ParentDepartmentGroupKey
FROM    dbo.DimDepartmentGroup
ORDER BY DepartmentGroupKey;
