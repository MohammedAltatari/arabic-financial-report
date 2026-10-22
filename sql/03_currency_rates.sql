-- =============================================
-- 03_currency_rates.sql
-- Step 1.3a: Check exchange rates before converting to USD
-- Run each block WITH the USE line
-- =============================================
USE AdventureWorksDW2022;
GO

-- (A) Yearly average rate for the currencies used by FactFinance
--     Goal: find the DIRECTION of the rate (foreign per 1 USD, or USD per 1 foreign?)
SELECT  c.CurrencyAlternateKey          AS Currency,
        c.CurrencyName,
        YEAR(r.[Date])                  AS RateYear,
        CAST(AVG(r.AverageRate) AS decimal(10,4)) AS AvgRate,
        COUNT(*)                        AS RateDays
FROM    dbo.FactCurrencyRate r
JOIN    dbo.DimCurrency c ON c.CurrencyKey = r.CurrencyKey
WHERE   c.CurrencyKey IN (SELECT DISTINCT CurrencyKey FROM dbo.DimOrganization)
GROUP BY c.CurrencyAlternateKey, c.CurrencyName, YEAR(r.[Date])
ORDER BY Currency, RateYear;

-- (B) Coverage: does every FactFinance row (non-USD branch) have a rate on its DateKey?
SELECT  c.CurrencyAlternateKey          AS Currency,
        COUNT(*)                        AS FactRows,
        SUM(CASE WHEN r.CurrencyKey IS NULL THEN 1 ELSE 0 END) AS RowsWithoutRate
FROM    dbo.FactFinance f
JOIN    dbo.DimOrganization o ON o.OrganizationKey = f.OrganizationKey
JOIN    dbo.DimCurrency     c ON c.CurrencyKey     = o.CurrencyKey
LEFT JOIN dbo.FactCurrencyRate r
        ON  r.CurrencyKey = o.CurrencyKey
        AND r.DateKey     = f.DateKey
GROUP BY c.CurrencyAlternateKey
ORDER BY Currency;
