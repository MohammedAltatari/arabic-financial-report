-- =============================================
-- 07_report_views.sql
-- Step 1.4: Clean reporting layer (Star Schema) in schema rpt
--   rpt.vw_DimAccount       Income Statement accounts + Arabic + sign + sort order
--   rpt.vw_DimDepartment    Departments + Arabic
--   rpt.vw_DimOrganization  Branches + Arabic + currency
--   rpt.vw_DimScenario      Scenarios + Arabic
--   rpt.vw_FactFinance      Facts in USD, fixed FinancePeriod, signed amount
-- Safe to re-run (CREATE OR ALTER)
-- =============================================
USE AdventureWorksDW2022;
GO

-- ---------------------------------------------
-- 1) Accounts: Income Statement tree only
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimAccount AS
WITH IncomeTree AS (
    SELECT  a.AccountKey,
            a.ParentAccountKey,
            0                       AS AccountLevel,
            CAST(1 AS int)          AS EffectiveSign,
            CAST(NULL AS int)       AS SectionKey,
            CAST('00000' AS varchar(500)) AS SortPath
    FROM    dbo.DimAccount a
    WHERE   a.ParentAccountKey IS NULL
      AND   a.AccountDescription = N'Net Income'

    UNION ALL

    SELECT  c.AccountKey,
            c.ParentAccountKey,
            t.AccountLevel + 1,
            t.EffectiveSign * CASE c.Operator WHEN '+' THEN 1 WHEN '-' THEN -1 ELSE 0 END,
            CASE WHEN c.AccountKey IN (50, 55, 58, 88, 94) THEN c.AccountKey ELSE t.SectionKey END,
            -- Gross Margin (49) is shown BEFORE Operating Expenses (58)
            CAST(t.SortPath + '/' +
                 CASE WHEN c.AccountKey = 49 THEN '00000'
                      ELSE RIGHT('00000' + CAST(c.AccountCodeAlternateKey AS varchar(10)), 5) END
                 AS varchar(500))
    FROM    dbo.DimAccount c
    JOIN    IncomeTree t ON c.ParentAccountKey = t.AccountKey
)
SELECT  it.AccountKey,
        it.ParentAccountKey,
        a.AccountDescription                      AS AccountNameEN,
        tr.AccountNameAR,
        it.AccountLevel,
        a.Operator,
        it.EffectiveSign,
        CASE WHEN EXISTS (SELECT 1 FROM dbo.DimAccount ch WHERE ch.ParentAccountKey = it.AccountKey)
             THEN 0 ELSE 1 END                    AS IsLeaf,
        COALESCE(sa.AccountDescription, N'Total') AS SectionEN,
        COALESCE(st.AccountNameAR,      N'إجمالي') AS SectionAR,
        CASE it.SectionKey WHEN 50 THEN 1 WHEN 55 THEN 2 WHEN 58 THEN 3
                           WHEN 88 THEN 4 WHEN 94 THEN 5 ELSE 0 END AS SectionOrder,
        ROW_NUMBER() OVER (ORDER BY it.SortPath)  AS AccountSortOrder
FROM    IncomeTree it
JOIN    dbo.DimAccount          a  ON a.AccountKey  = it.AccountKey
LEFT JOIN rpt.AccountTranslation tr ON tr.AccountKey = it.AccountKey
LEFT JOIN dbo.DimAccount          sa ON sa.AccountKey = it.SectionKey
LEFT JOIN rpt.AccountTranslation  st ON st.AccountKey = it.SectionKey;
GO

-- ---------------------------------------------
-- 2) Departments
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimDepartment AS
SELECT  d.DepartmentGroupKey,
        d.ParentDepartmentGroupKey,
        d.DepartmentGroupName AS DepartmentNameEN,
        t.DepartmentNameAR
FROM    dbo.DimDepartmentGroup d
LEFT JOIN rpt.DepartmentTranslation t ON t.DepartmentGroupKey = d.DepartmentGroupKey;
GO

-- ---------------------------------------------
-- 3) Organizations (branches)
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimOrganization AS
SELECT  o.OrganizationKey,
        o.ParentOrganizationKey,
        o.OrganizationName      AS OrganizationNameEN,
        t.OrganizationNameAR,
        c.CurrencyAlternateKey  AS CurrencyCode
FROM    dbo.DimOrganization o
LEFT JOIN rpt.OrganizationTranslation t ON t.OrganizationKey = o.OrganizationKey
LEFT JOIN dbo.DimCurrency             c ON c.CurrencyKey     = o.CurrencyKey;
GO

-- ---------------------------------------------
-- 4) Scenarios
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimScenario AS
SELECT  s.ScenarioKey,
        s.ScenarioName   AS ScenarioNameEN,
        t.ScenarioNameAR
FROM    dbo.DimScenario s
LEFT JOIN rpt.ScenarioTranslation t ON t.ScenarioName = s.ScenarioName;
GO

-- ---------------------------------------------
-- 5) Fact: Income Statement rows only, in USD
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_FactFinance AS
SELECT  f.FinanceKey,
        f.DateKey                                   AS OriginalDateKey,
        DATEFROMPARTS(YEAR(DATEADD(day, -5, d.FullDateAlternateKey)),
                      MONTH(DATEADD(day, -5, d.FullDateAlternateKey)), 1) AS FinancePeriod,
        f.ScenarioKey,
        f.OrganizationKey,
        f.DepartmentGroupKey,
        f.AccountKey,
        f.Amount                                    AS AmountLocal,
        r.AverageRate                               AS RateToUSD,
        f.Amount * r.AverageRate                    AS AmountUSD,
        f.Amount * r.AverageRate * acc.EffectiveSign AS SignedAmountUSD
FROM    dbo.FactFinance      f
JOIN    rpt.vw_DimAccount    acc ON acc.AccountKey     = f.AccountKey   -- keeps Income Statement only
JOIN    dbo.DimDate          d   ON d.DateKey          = f.DateKey
JOIN    dbo.DimOrganization  o   ON o.OrganizationKey  = f.OrganizationKey
JOIN    dbo.FactCurrencyRate r   ON r.CurrencyKey      = o.CurrencyKey
                                AND r.DateKey          = f.DateKey;
GO

-- =============================================
-- CHECKS
-- =============================================

-- (Check 1) No rows lost: both numbers must be equal
SELECT  (SELECT COUNT(*) FROM rpt.vw_FactFinance) AS ViewRows,
        (SELECT COUNT(*) FROM dbo.FactFinance f
         WHERE f.AccountKey IN (SELECT AccountKey FROM rpt.vw_DimAccount)) AS SourceRows;

-- (Check 2) Net Income by year must match 04_income_statement.sql
--           Actual: 2010 = -237,699 | 2011 = 4,903,969 | 2012 = 6,123,842 | 2013 = 7,371,083
SELECT  s.ScenarioNameEN,
        YEAR(v.FinancePeriod)                        AS [Year],
        CAST(SUM(v.SignedAmountUSD) AS decimal(18,0)) AS NetIncomeUSD
FROM    rpt.vw_FactFinance v
JOIN    rpt.vw_DimScenario s ON s.ScenarioKey = v.ScenarioKey
GROUP BY s.ScenarioNameEN, YEAR(v.FinancePeriod)
ORDER BY [Year], s.ScenarioNameEN;

-- (Check 3) Operating Profit Dec 2010 .. Nov 2011 must match 05_budget_vs_actual.sql
--           Actual = 5,508,435 | Budget = 7,422,755
SELECT  s.ScenarioNameEN,
        CAST(SUM(v.SignedAmountUSD) AS decimal(18,0)) AS OperatingProfitUSD
FROM    rpt.vw_FactFinance v
JOIN    rpt.vw_DimScenario s ON s.ScenarioKey = v.ScenarioKey
JOIN    rpt.vw_DimAccount  a ON a.AccountKey  = v.AccountKey
WHERE   v.FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01'
  AND   a.SectionOrder BETWEEN 1 AND 3
GROUP BY s.ScenarioNameEN;

-- (Check 4) Account display order (should read like an Income Statement)
SELECT  AccountSortOrder,
        REPLICATE(N'    ', AccountLevel) + AccountNameAR AS AccountAR,
        AccountNameEN, EffectiveSign, SectionAR, IsLeaf
FROM    rpt.vw_DimAccount
ORDER BY AccountSortOrder;
