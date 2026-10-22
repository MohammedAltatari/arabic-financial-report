-- =============================================
-- 08_dim_date.sql
-- Step 2.2a: Date dimension for Excel and Power BI (same table in both)
--   * One row per DAY, full calendar years 2010-01-01 .. 2013-12-31
--     (Power BI time intelligence needs contiguous days and full years)
--   * FactFinance joins on FinancePeriod (first day of each month)
--   * Arabic + English month and quarter names, sort keys
-- Safe to re-run (CREATE OR ALTER)
-- =============================================
USE AdventureWorksDW2022;
GO

CREATE OR ALTER VIEW rpt.vw_DimDate AS
WITH Numbers AS (
    SELECT TOP (DATEDIFF(day, '2010-01-01', '2013-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM   sys.all_columns a CROSS JOIN sys.all_columns b
),
Dates AS (
    SELECT DATEADD(day, n, CAST('2010-01-01' AS date)) AS [Date]
    FROM   Numbers
)
SELECT  [Date],
        YEAR([Date])                                    AS [Year],
        DATEPART(quarter, [Date])                       AS QuarterNumber,
        N'Q' + CAST(DATEPART(quarter, [Date]) AS nvarchar(1)) AS QuarterEN,
        CASE DATEPART(quarter, [Date])
             WHEN 1 THEN N'الربع الأول'  WHEN 2 THEN N'الربع الثاني'
             WHEN 3 THEN N'الربع الثالث' ELSE N'الربع الرابع' END AS QuarterAR,
        MONTH([Date])                                   AS MonthNumber,
        DATENAME(month, [Date])                         AS MonthNameEN,
        LEFT(DATENAME(month, [Date]), 3)                AS MonthShortEN,
        CASE MONTH([Date])
             WHEN 1 THEN N'يناير'   WHEN 2 THEN N'فبراير'  WHEN 3 THEN N'مارس'
             WHEN 4 THEN N'أبريل'   WHEN 5 THEN N'مايو'    WHEN 6 THEN N'يونيو'
             WHEN 7 THEN N'يوليو'   WHEN 8 THEN N'أغسطس'   WHEN 9 THEN N'سبتمبر'
             WHEN 10 THEN N'أكتوبر' WHEN 11 THEN N'نوفمبر' ELSE N'ديسمبر' END AS MonthNameAR,
        YEAR([Date]) * 100 + MONTH([Date])              AS YearMonthKey,      -- sort key, e.g. 201103
        LEFT(DATENAME(month, [Date]), 3) + N' ' + CAST(YEAR([Date]) AS nvarchar(4)) AS MonthYearEN,   -- e.g. Mar 2011
        DATEFROMPARTS(YEAR([Date]), MONTH([Date]), 1)   AS MonthStart,
        CASE WHEN [Date] = DATEFROMPARTS(YEAR([Date]), MONTH([Date]), 1) THEN 1 ELSE 0 END AS IsMonthStart
FROM    Dates;
GO

-- =============================================
-- CHECKS
-- =============================================

-- (Check 1) 1461 days, from 2010-01-01 to 2013-12-31, no duplicates
SELECT  COUNT(*)               AS Days,
        COUNT(DISTINCT [Date]) AS DistinctDays,
        MIN([Date])            AS FirstDate,
        MAX([Date])            AS LastDate
FROM    rpt.vw_DimDate;

-- (Check 2) Every FinancePeriod in the fact view exists in the date table
--           Expected: 0 rows
SELECT DISTINCT f.FinancePeriod AS MissingInDimDate
FROM   rpt.vw_FactFinance f
LEFT JOIN rpt.vw_DimDate d ON d.[Date] = f.FinancePeriod
WHERE  d.[Date] IS NULL;

-- (Check 3) Arabic month names (12 rows)
SELECT DISTINCT MonthNumber, MonthNameEN, MonthNameAR
FROM   rpt.vw_DimDate
ORDER BY MonthNumber;
