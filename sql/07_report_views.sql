-- =============================================
-- 07_report_views.sql
-- Step 1.4: Clean reporting layer (Star Schema) in schema rpt
--   rpt.vw_DimAccount       Income Statement accounts + Arabic + sign + sort order
--                           + Section -> Group -> Account hierarchy (Step 2.4b)
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
CREATE OR ALTER VIEW rpt.vw_DimAccount
AS
WITH   IncomeTree
AS     (SELECT a.AccountKey,
               a.ParentAccountKey,
               0 AS AccountLevel,
               CAST (1 AS INT) AS EffectiveSign,
               CAST (NULL AS INT) AS SectionKey,
               CAST (NULL AS INT) AS GroupKey,
               CAST ('00000' AS VARCHAR (500)) AS SortPath,
               CAST (NULL AS VARCHAR (500)) AS GroupSortPath
        FROM   dbo.DimAccount AS a
        WHERE  a.ParentAccountKey IS NULL
               AND a.AccountDescription = N'Net Income'
        UNION ALL
        SELECT c.AccountKey,
               c.ParentAccountKey,
               t.AccountLevel + 1,
               t.EffectiveSign * CASE c.Operator WHEN '+' THEN 1 WHEN '-' THEN -1 ELSE 0 END,
               CASE WHEN c.AccountKey IN (50, 55, 58, 88, 94) THEN c.AccountKey ELSE t.SectionKey END,
               -- Group = the first level under a section (e.g. Labor Expenses under Operating Expenses).
               -- A section with no children (Taxes) is its own group.
               CASE WHEN c.AccountKey IN (50, 55, 58, 88, 94) THEN c.AccountKey WHEN t.AccountKey IN (50, 55, 58, 88, 94) THEN c.AccountKey ELSE t.GroupKey END,
               -- Gross Margin (49) is shown BEFORE Operating Expenses (58)
               CAST (t.SortPath + '/' + CASE WHEN c.AccountKey = 49 THEN '00000' ELSE RIGHT('00000' + CAST (c.AccountCodeAlternateKey AS VARCHAR (10)), 5) END AS VARCHAR (500)),
               CAST (CASE WHEN c.AccountKey IN (50, 55, 58, 88, 94)
                               OR t.AccountKey IN (50, 55, 58, 88, 94) THEN t.SortPath + '/' + RIGHT('00000' + CAST (c.AccountCodeAlternateKey AS VARCHAR (10)), 5) ELSE t.GroupSortPath END AS VARCHAR (500))
        FROM   dbo.DimAccount AS c
               INNER JOIN
               IncomeTree AS t
               ON c.ParentAccountKey = t.AccountKey)
SELECT it.AccountKey,
       it.ParentAccountKey,
       a.AccountDescription AS AccountNameEN,
       tr.AccountNameAR,
       it.AccountLevel,
       a.Operator,
       it.EffectiveSign,
       CASE WHEN EXISTS (SELECT 1
                         FROM   dbo.DimAccount AS ch
                         WHERE  ch.ParentAccountKey = it.AccountKey) THEN 0 ELSE 1 END AS IsLeaf,
       COALESCE (sa.AccountDescription, N'Total') AS SectionEN,
       COALESCE (st.AccountNameAR, N'إجمالي') AS SectionAR,
       CASE it.SectionKey WHEN 50 THEN 1 WHEN 55 THEN 2 WHEN 58 THEN 3 WHEN 88 THEN 4 WHEN 94 THEN 5 ELSE 0 END AS SectionOrder,
       ROW_NUMBER() OVER (ORDER BY it.SortPath) AS AccountSortOrder,
       COALESCE (ga.AccountDescription, N'Total') AS GroupEN,
       COALESCE (gt.AccountNameAR, N'إجمالي') AS GroupAR,
       DENSE_RANK() OVER (ORDER BY COALESCE (it.GroupSortPath, '')) AS GroupOrder
FROM   IncomeTree AS it
       INNER JOIN
       dbo.DimAccount AS a
       ON a.AccountKey = it.AccountKey
       LEFT OUTER JOIN
       rpt.AccountTranslation AS tr
       ON tr.AccountKey = it.AccountKey
       LEFT OUTER JOIN
       dbo.DimAccount AS sa
       ON sa.AccountKey = it.SectionKey
       LEFT OUTER JOIN
       rpt.AccountTranslation AS st
       ON st.AccountKey = it.SectionKey
       LEFT OUTER JOIN
       dbo.DimAccount AS ga
       ON ga.AccountKey = it.GroupKey
       LEFT OUTER JOIN
       rpt.AccountTranslation AS gt
       ON gt.AccountKey = it.GroupKey;


GO
-- ---------------------------------------------
-- 2) Departments
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimDepartment
AS
SELECT d.DepartmentGroupKey,
       d.ParentDepartmentGroupKey,
       d.DepartmentGroupName AS DepartmentNameEN,
       t.DepartmentNameAR
FROM   dbo.DimDepartmentGroup AS d
       LEFT OUTER JOIN
       rpt.DepartmentTranslation AS t
       ON t.DepartmentGroupKey = d.DepartmentGroupKey;


GO
-- ---------------------------------------------
-- 3) Organizations (branches)
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimOrganization
AS
SELECT o.OrganizationKey,
       o.ParentOrganizationKey,
       o.OrganizationName AS OrganizationNameEN,
       t.OrganizationNameAR,
       c.CurrencyAlternateKey AS CurrencyCode
FROM   dbo.DimOrganization AS o
       LEFT OUTER JOIN
       rpt.OrganizationTranslation AS t
       ON t.OrganizationKey = o.OrganizationKey
       LEFT OUTER JOIN
       dbo.DimCurrency AS c
       ON c.CurrencyKey = o.CurrencyKey;


GO
-- ---------------------------------------------
-- 4) Scenarios
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_DimScenario
AS
SELECT s.ScenarioKey,
       s.ScenarioName AS ScenarioNameEN,
       t.ScenarioNameAR
FROM   dbo.DimScenario AS s
       LEFT OUTER JOIN
       rpt.ScenarioTranslation AS t
       ON t.ScenarioName = s.ScenarioName;


GO
-- ---------------------------------------------
-- 5) Fact: Income Statement rows only, in USD
-- ---------------------------------------------
CREATE OR ALTER VIEW rpt.vw_FactFinance
AS
SELECT f.FinanceKey,
       f.DateKey AS OriginalDateKey,
       DATEFROMPARTS(YEAR(DATEADD(day, -5, d.FullDateAlternateKey)), MONTH(DATEADD(day, -5, d.FullDateAlternateKey)), 1) AS FinancePeriod,
       f.ScenarioKey,
       f.OrganizationKey,
       f.DepartmentGroupKey,
       f.AccountKey,
       f.Amount AS AmountLocal,
       r.AverageRate AS RateToUSD,
       f.Amount * r.AverageRate AS AmountUSD,
       f.Amount * r.AverageRate * acc.EffectiveSign AS SignedAmountUSD
FROM   dbo.FactFinance AS f
       INNER JOIN
       rpt.vw_DimAccount AS acc
       ON acc.AccountKey = f.AccountKey -- keeps Income Statement only
       INNER JOIN
       dbo.DimDate AS d
       ON d.DateKey = f.DateKey
       INNER JOIN
       dbo.DimOrganization AS o
       ON o.OrganizationKey = f.OrganizationKey
       INNER JOIN
       dbo.FactCurrencyRate AS r
       ON r.CurrencyKey = o.CurrencyKey
          AND r.DateKey = f.DateKey;


GO
-- =============================================
-- CHECKS
-- =============================================
-- (Check 1) No rows lost: both numbers must be equal
SELECT (SELECT COUNT(*)
        FROM   rpt.vw_FactFinance) AS ViewRows,
       (SELECT COUNT(*)
        FROM   dbo.FactFinance AS f
        WHERE  f.AccountKey IN (SELECT AccountKey
                                FROM   rpt.vw_DimAccount)) AS SourceRows;

-- (Check 2) Net Income by year must match 04_income_statement.sql
--           Actual: 2010 = -237,699 | 2011 = 4,903,969 | 2012 = 6,123,842 | 2013 = 7,371,083
SELECT   s.ScenarioNameEN,
         YEAR(v.FinancePeriod) AS [Year],
         CAST (SUM(v.SignedAmountUSD) AS DECIMAL (18, 0)) AS NetIncomeUSD
FROM     rpt.vw_FactFinance AS v
         INNER JOIN
         rpt.vw_DimScenario AS s
         ON s.ScenarioKey = v.ScenarioKey
GROUP BY s.ScenarioNameEN, YEAR(v.FinancePeriod)
ORDER BY [Year], s.ScenarioNameEN;

-- (Check 3) Operating Profit Dec 2010 .. Nov 2011 must match 05_budget_vs_actual.sql
--           Actual = 5,508,435 | Budget = 7,422,755
SELECT   s.ScenarioNameEN,
         CAST (SUM(v.SignedAmountUSD) AS DECIMAL (18, 0)) AS OperatingProfitUSD
FROM     rpt.vw_FactFinance AS v
         INNER JOIN
         rpt.vw_DimScenario AS s
         ON s.ScenarioKey = v.ScenarioKey
         INNER JOIN
         rpt.vw_DimAccount AS a
         ON a.AccountKey = v.AccountKey
WHERE    v.FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01'
         AND a.SectionOrder BETWEEN 1 AND 3
GROUP BY s.ScenarioNameEN;

-- (Check 4) Account display order (should read like an Income Statement)
SELECT   AccountSortOrder,
         REPLICATE(N'    ', AccountLevel) + AccountNameAR AS AccountAR,
         AccountNameEN,
         EffectiveSign,
         SectionAR,
         IsLeaf
FROM     rpt.vw_DimAccount
ORDER BY AccountSortOrder;

-- (Check 5) Section -> Group hierarchy (Step 2.4b): expected 26 rows, in income-statement order
SELECT   GroupOrder,
         SectionAR,
         GroupAR,
         GroupEN,
         COUNT(*) AS Accounts,
         SUM(IsLeaf) AS LeafAccounts
FROM     rpt.vw_DimAccount
GROUP BY GroupOrder, SectionAR, GroupAR, GroupEN
ORDER BY GroupOrder;