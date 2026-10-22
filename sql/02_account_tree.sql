-- =============================================
-- 02_account_tree.sql
-- Step 1.2: Understand the chart of accounts (Parent-Child) and Operator
-- Run each block WITH the USE line (select both, then Ctrl+Shift+E)
-- =============================================
USE AdventureWorksDW2022;
GO

-- (A) Full account tree, indented, in the correct order
WITH AccountTree AS (
    -- Anchor: the root account(s) (no parent)
    SELECT  a.AccountKey,
            a.ParentAccountKey,
            a.AccountCodeAlternateKey,
            a.AccountDescription,
            a.AccountType,
            a.Operator,
            0 AS Lvl,
            CAST(RIGHT('00000' + CAST(a.AccountCodeAlternateKey AS varchar(10)), 5) AS varchar(500)) AS SortPath
    FROM    dbo.DimAccount a
    WHERE   a.ParentAccountKey IS NULL

    UNION ALL

    -- Recursive part: children of the previous level
    SELECT  c.AccountKey,
            c.ParentAccountKey,
            c.AccountCodeAlternateKey,
            c.AccountDescription,
            c.AccountType,
            c.Operator,
            t.Lvl + 1,
            CAST(t.SortPath + '/' + RIGHT('00000' + CAST(c.AccountCodeAlternateKey AS varchar(10)), 5) AS varchar(500))
    FROM    dbo.DimAccount c
    JOIN    AccountTree t ON c.ParentAccountKey = t.AccountKey
)
SELECT  REPLICATE(N'    ', t.Lvl) + t.AccountDescription AS Account,
        t.AccountKey,
        t.ParentAccountKey,
        t.Lvl,
        t.Operator,
        t.AccountType,
        (SELECT COUNT(*) FROM dbo.FactFinance f WHERE f.AccountKey = t.AccountKey) AS FactRows
FROM    AccountTree t
ORDER BY t.SortPath;

-- (B) How many accounts per Operator and AccountType
SELECT  Operator,
        AccountType,
        COUNT(*) AS Accounts
FROM    dbo.DimAccount
GROUP BY Operator, AccountType
ORDER BY Operator, AccountType;

-- (C) Effective sign of each Income Statement account
--     Sign = product of Operators on the path from the account up to "Net Income"
--     +1 = adds to Net Income, -1 = reduces Net Income
WITH IncomeTree AS (
    SELECT  a.AccountKey,
            a.AccountDescription,
            a.AccountType,
            0 AS Lvl,
            CAST(1 AS int) AS EffectiveSign,
            CAST(RIGHT('00000' + CAST(a.AccountCodeAlternateKey AS varchar(10)), 5) AS varchar(500)) AS SortPath
    FROM    dbo.DimAccount a
    WHERE   a.ParentAccountKey IS NULL
      AND   a.AccountDescription = 'Net Income'

    UNION ALL

    SELECT  c.AccountKey,
            c.AccountDescription,
            c.AccountType,
            t.Lvl + 1,
            t.EffectiveSign * CASE c.Operator WHEN '+' THEN 1 WHEN '-' THEN -1 ELSE 0 END,
            CAST(t.SortPath + '/' + RIGHT('00000' + CAST(c.AccountCodeAlternateKey AS varchar(10)), 5) AS varchar(500))
    FROM    dbo.DimAccount c
    JOIN    IncomeTree t ON c.ParentAccountKey = t.AccountKey
)
SELECT  REPLICATE(N'    ', Lvl) + AccountDescription AS Account,
        AccountKey,
        AccountType,
        EffectiveSign
FROM    IncomeTree
ORDER BY SortPath;
