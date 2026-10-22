-- =============================================
-- 05_budget_vs_actual.sql
-- Step 1.3 (final): Budget vs Actual, Dec 2010 .. Nov 2011, in USD
-- Rules applied:
--   * Net Income tree only, EffectiveSign (expenses negative)
--   * USD = Amount * AverageRate
--   * FinancePeriod = month of (date - 5 days)   -- fixes shifted DateKeys
--   * Comparison at Operating Profit level (Budget has no Taxes / Other Income)
-- Because expenses are already negative:
--   Variance = Actual - Budget  ->  positive = Favorable, negative = Unfavorable
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
            f.Amount * r.AverageRate * it.EffectiveSign AS SignedUSD
    FROM    dbo.FactFinance      f
    JOIN    IncomeTree           it ON it.AccountKey     = f.AccountKey
    JOIN    dbo.DimScenario      s  ON s.ScenarioKey     = f.ScenarioKey
    JOIN    dbo.DimDate          d  ON d.DateKey         = f.DateKey
    JOIN    dbo.DimOrganization  o  ON o.OrganizationKey = f.OrganizationKey
    JOIN    dbo.FactCurrencyRate r  ON r.CurrencyKey     = o.CurrencyKey
                                   AND r.DateKey         = f.DateKey
),
Totals AS (
    SELECT  SUM(CASE WHEN ScenarioName = 'Actual' AND Section = N'Net Sales'           THEN SignedUSD ELSE 0 END) AS A_Sales,
            SUM(CASE WHEN ScenarioName = 'Budget' AND Section = N'Net Sales'           THEN SignedUSD ELSE 0 END) AS B_Sales,
            SUM(CASE WHEN ScenarioName = 'Actual' AND Section = N'Total Cost of Sales' THEN SignedUSD ELSE 0 END) AS A_COGS,
            SUM(CASE WHEN ScenarioName = 'Budget' AND Section = N'Total Cost of Sales' THEN SignedUSD ELSE 0 END) AS B_COGS,
            SUM(CASE WHEN ScenarioName = 'Actual' AND Section = N'Operating Expenses'  THEN SignedUSD ELSE 0 END) AS A_OpEx,
            SUM(CASE WHEN ScenarioName = 'Budget' AND Section = N'Operating Expenses'  THEN SignedUSD ELSE 0 END) AS B_OpEx
    FROM    FinanceUSD
    WHERE   FinancePeriod BETWEEN '2010-12-01' AND '2011-11-01'
),
Lines AS (
    SELECT  v.SortOrder, v.LineName, v.Actual, v.Budget
    FROM    Totals t
    CROSS APPLY (VALUES
        (1, N'Net Sales',          t.A_Sales,                         t.B_Sales),
        (2, N'Cost of Sales',      t.A_COGS,                          t.B_COGS),
        (3, N'Gross Margin',       t.A_Sales + t.A_COGS,              t.B_Sales + t.B_COGS),
        (4, N'Operating Expenses', t.A_OpEx,                          t.B_OpEx),
        (5, N'Operating Profit',   t.A_Sales + t.A_COGS + t.A_OpEx,   t.B_Sales + t.B_COGS + t.B_OpEx)
    ) v (SortOrder, LineName, Actual, Budget)
)
SELECT  LineName,
        CAST(Actual          AS decimal(18,0)) AS Actual,
        CAST(Budget          AS decimal(18,0)) AS Budget,
        CAST(Actual - Budget AS decimal(18,0)) AS Variance,
        CAST(100.0 * (Actual - Budget) / NULLIF(ABS(Budget), 0) AS decimal(9,1)) AS VariancePct,
        CASE WHEN Actual - Budget >= 0 THEN 'Favorable' ELSE 'Unfavorable' END AS Status
FROM    Lines
ORDER BY SortOrder;
