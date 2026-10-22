-- =============================================
-- 04_income_statement.sql
-- Step 1.3: Simplified Income Statement in USD, by Scenario and Year
-- Rules applied:
--   * Only the "Net Income" tree (Balance Sheet & Statistical excluded)
--   * EffectiveSign = product of Operators up to Net Income (+1 / -1)
--   * Local currency -> USD:  Amount * AverageRate  (rate = USD per 1 unit)
-- Expenses/costs appear NEGATIVE (they reduce profit)
-- =============================================
USE AdventureWorksDW2022;
GO

WITH IncomeTree AS (
    -- Root: Net Income
    SELECT  a.AccountKey,
            CAST(1 AS int)               AS EffectiveSign,
            CAST(NULL AS nvarchar(50))   AS Section
    FROM    dbo.DimAccount a
    WHERE   a.ParentAccountKey IS NULL
      AND   a.AccountDescription = N'Net Income'

    UNION ALL

    -- Children: multiply signs, and inherit the income-statement section
    SELECT  c.AccountKey,
            t.EffectiveSign * CASE c.Operator WHEN '+' THEN 1 WHEN '-' THEN -1 ELSE 0 END,
            CAST(CASE WHEN c.AccountDescription IN (N'Net Sales', N'Total Cost of Sales',
                                                    N'Operating Expenses', N'Other Income and Expense',
                                                    N'Taxes')
                      THEN c.AccountDescription
                      ELSE t.Section END AS nvarchar(50))
    FROM    dbo.DimAccount c
    JOIN    IncomeTree t ON c.ParentAccountKey = t.AccountKey
),
FinanceUSD AS (
    SELECT  s.ScenarioName,
            d.CalendarYear,
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
Summary AS (
    SELECT  ScenarioName,
            CalendarYear,
            CAST(SUM(CASE WHEN Section = N'Net Sales'                THEN SignedUSD ELSE 0 END) AS decimal(18,0)) AS NetSales,
            CAST(SUM(CASE WHEN Section = N'Total Cost of Sales'      THEN SignedUSD ELSE 0 END) AS decimal(18,0)) AS CostOfSales,
            CAST(SUM(CASE WHEN Section = N'Operating Expenses'       THEN SignedUSD ELSE 0 END) AS decimal(18,0)) AS OperatingExpenses,
            CAST(SUM(CASE WHEN Section = N'Other Income and Expense' THEN SignedUSD ELSE 0 END) AS decimal(18,0)) AS OtherIncomeExpense,
            CAST(SUM(CASE WHEN Section = N'Taxes'                    THEN SignedUSD ELSE 0 END) AS decimal(18,0)) AS Taxes,
            CAST(SUM(SignedUSD) AS decimal(18,0))                                                                  AS NetIncome_Check
    FROM    FinanceUSD
    GROUP BY ScenarioName, CalendarYear
)
SELECT  ScenarioName,
        CalendarYear,
        NetSales,
        CostOfSales,
        NetSales + CostOfSales                                          AS GrossMargin,
        CAST(100.0 * (NetSales + CostOfSales) / NULLIF(NetSales, 0) AS decimal(9,1)) AS GrossMarginPct,
        OperatingExpenses,
        NetSales + CostOfSales + OperatingExpenses                      AS OperatingProfit,
        OtherIncomeExpense,
        Taxes,
        NetSales + CostOfSales + OperatingExpenses + OtherIncomeExpense + Taxes AS NetIncome,
        CAST(100.0 * (NetSales + CostOfSales + OperatingExpenses + OtherIncomeExpense + Taxes)
                   / NULLIF(NetSales, 0) AS decimal(9,1))               AS NetMarginPct,
        NetIncome_Check
FROM    Summary
ORDER BY CalendarYear, ScenarioName;

-- (B) Which months have Actual and/or Budget? (2010-2011)
--     Budget vs Actual must compare the SAME months only
SELECT  d.CalendarYear,
        d.MonthNumberOfYear,
        SUM(CASE WHEN s.ScenarioName = 'Actual' THEN 1 ELSE 0 END) AS ActualRows,
        SUM(CASE WHEN s.ScenarioName = 'Budget' THEN 1 ELSE 0 END) AS BudgetRows
FROM    dbo.FactFinance f
JOIN    dbo.DimScenario s ON s.ScenarioKey = f.ScenarioKey
JOIN    dbo.DimDate     d ON d.DateKey     = f.DateKey
WHERE   d.CalendarYear IN (2010, 2011)
GROUP BY d.CalendarYear, d.MonthNumberOfYear
ORDER BY d.CalendarYear, d.MonthNumberOfYear;

-- (C) Months 3, 5, 8 have DOUBLE rows and months 2, 4, 6 are missing.
--     Are the extra rows duplicates, or another month stored on a different day?
SELECT  f.DateKey,
        s.ScenarioName,
        COUNT(*)                          AS Rows,
        CAST(SUM(f.Amount) AS decimal(18,0)) AS RawAmount
FROM    dbo.FactFinance f
JOIN    dbo.DimScenario s ON s.ScenarioKey = f.ScenarioKey
WHERE   f.DateKey BETWEEN 20101201 AND 20111231
GROUP BY f.DateKey, s.ScenarioName
ORDER BY f.DateKey, s.ScenarioName;

-- (D) Proposed fix: map each DateKey to its real accounting period
--     Rule: period = month of (date - 5 days)
--     Expected: 37 consecutive periods (Dec 2010 .. Dec 2013), no gaps
WITH Dates AS (
    SELECT DISTINCT
           f.DateKey,
           CONVERT(date, CAST(f.DateKey AS char(8)), 112) AS RawDate
    FROM   dbo.FactFinance f
),
Mapped AS (
    SELECT DateKey,
           RawDate,
           DATEFROMPARTS(YEAR(DATEADD(day, -5, RawDate)), MONTH(DATEADD(day, -5, RawDate)), 1) AS FinancePeriod
    FROM   Dates
)
SELECT  FinancePeriod,
        COUNT(*)      AS DatesInPeriod,
        MIN(DateKey)  AS FirstDateKey,
        MAX(DateKey)  AS LastDateKey,
        DATEDIFF(month, LAG(FinancePeriod) OVER (ORDER BY FinancePeriod), FinancePeriod) AS GapFromPrevious  -- should be 1
FROM    Mapped
GROUP BY FinancePeriod
ORDER BY FinancePeriod;
