-- =============================================
-- 09_reconciliation.sql
-- Step 4.1: Reference totals to reconcile SQL vs Excel vs Power BI
-- Built directly on the dbo source tables (NOT the rpt views),
-- so it is an independent check of the whole pipeline.
-- Rules (same as 05_budget_vs_actual.sql):
--   * Net Income tree only, EffectiveSign (expenses negative)
--   * USD = Amount * AverageRate
--   * FinancePeriod = month of (date - 5 days)
--   * Budget period = Dec 2010 .. Nov 2011
--   * Rolling forecast (cutoff May 2011) = Actual Dec 2010..May 2011
--                                        + Budget Jun 2011..Nov 2011
-- =============================================
USE AdventureWorksDW2022;
GO

WITH IncomeTree AS (
    SELECT  a.AccountKey,
            CAST(1 AS int)             AS EffectiveSign,
            CAST(NULL AS nvarchar(50)) AS Section
    FROM    dbo.DimAccount a
    WHERE   a.ParentAccountKey IS NULL
      AND   a.AccountDescription = N'Net Income'
    UNION ALL
    SELECT  c.AccountKey,
            t.EffectiveSign * CASE c.Operator WHEN '+' THEN 1 WHEN '-' THEN -1 ELSE 0 END,
            CAST(CASE WHEN c.AccountDescription IN (N'Net Sales', N'Total Cost of Sales',
                                                    N'Operating Expenses', N'Other Income and Expense',
                                                    N'Taxes')
                      THEN c.AccountDescription ELSE t.Section END AS nvarchar(50))
    FROM    dbo.DimAccount c
    JOIN    IncomeTree t ON c.ParentAccountKey = t.AccountKey
),
FinanceUSD AS (
    SELECT  s.ScenarioName,
            DATEFROMPARTS(YEAR(DATEADD(day, -5, d.FullDateAlternateKey)),
                          MONTH(DATEADD(day, -5, d.FullDateAlternateKey)), 1) AS FinancePeriod,
            it.Section,
            CASE WHEN it.Section IN (N'Net Sales', N'Total Cost of Sales', N'Operating Expenses')
                 THEN 1 ELSE 0 END                         AS IsOperating,
            f.Amount * r.AverageRate * it.EffectiveSign    AS SignedUSD
    FROM    dbo.FactFinance      f
    JOIN    IncomeTree           it ON it.AccountKey     = f.AccountKey
    JOIN    dbo.DimScenario      s  ON s.ScenarioKey     = f.ScenarioKey
    JOIN    dbo.DimDate          d  ON d.DateKey         = f.DateKey
    JOIN    dbo.DimOrganization  o  ON o.OrganizationKey = f.OrganizationKey
    JOIN    dbo.FactCurrencyRate r  ON r.CurrencyKey     = o.CurrencyKey
                                   AND r.DateKey         = f.DateKey
),
Checks AS (
    SELECT
        -- Budget period: Dec 2010 .. Nov 2011
        SUM(CASE WHEN ScenarioName = 'Actual' AND Section = N'Net Sales'
                  AND FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01' THEN SignedUSD ELSE 0 END) AS NetSalesActual,
        SUM(CASE WHEN ScenarioName = 'Budget' AND Section = N'Net Sales'
                  AND FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01' THEN SignedUSD ELSE 0 END) AS NetSalesBudget,
        SUM(CASE WHEN ScenarioName = 'Actual' AND IsOperating = 1
                  AND FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01' THEN SignedUSD ELSE 0 END) AS OpActual,
        SUM(CASE WHEN ScenarioName = 'Budget' AND IsOperating = 1
                  AND FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01' THEN SignedUSD ELSE 0 END) AS OpBudget,
        -- Rolling forecast, cutoff May 2011
        SUM(CASE WHEN IsOperating = 1 AND (
                     (ScenarioName = 'Actual' AND FinancePeriod BETWEEN '2010-12-01' AND '2011-05-01')
                  OR (ScenarioName = 'Budget' AND FinancePeriod BETWEEN '2011-06-01' AND '2011-11-01'))
                 THEN SignedUSD ELSE 0 END)                                                     AS OpForecast,
        -- Net Income (Actual)
        SUM(CASE WHEN ScenarioName = 'Actual'
                  AND FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01' THEN SignedUSD ELSE 0 END) AS NiBudgetPeriod,
        SUM(CASE WHEN ScenarioName = 'Actual' AND YEAR(FinancePeriod) = 2012 THEN SignedUSD ELSE 0 END) AS Ni2012,
        SUM(CASE WHEN ScenarioName = 'Actual' AND YEAR(FinancePeriod) = 2013 THEN SignedUSD ELSE 0 END) AS Ni2013
    FROM FinanceUSD
)
SELECT  v.CheckNo, v.CheckName, CAST(ROUND(v.SqlValue, 0) AS decimal(19, 0)) AS SqlValue
FROM    Checks c
CROSS APPLY (VALUES
    (1, N'Net Sales - Actual (budget period)',       c.NetSalesActual),
    (2, N'Net Sales - Budget',                       c.NetSalesBudget),
    (3, N'Operating Profit - Actual (budget period)', c.OpActual),
    (4, N'Operating Profit - Budget',                c.OpBudget),
    (5, N'Operating Profit - Variance',              c.OpActual - c.OpBudget),
    (6, N'Operating Profit - Rolling Forecast (May 2011)', c.OpForecast),
    (7, N'Net Income - Actual (budget period)',      c.NiBudgetPeriod),
    (8, N'Net Income - Actual 2012',                 c.Ni2012),
    (9, N'Net Income - Actual 2013',                 c.Ni2013)
) AS v (CheckNo, CheckName, SqlValue)
ORDER BY v.CheckNo;
