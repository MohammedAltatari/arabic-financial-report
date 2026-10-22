-- =============================================
-- 06_translation_tables.sql
-- Step 1.5: Arabic translation tables (schema: rpt)
-- Safe to re-run: drops and recreates the tables
-- IMPORTANT: every Arabic string uses the N'' prefix (NVARCHAR)
-- =============================================
USE AdventureWorksDW2022;
GO

IF SCHEMA_ID('rpt') IS NULL
    EXEC('CREATE SCHEMA rpt');
GO

-- ---------------------------------------------
-- 1) Accounts (Income Statement tree only)
-- ---------------------------------------------
DROP TABLE IF EXISTS rpt.AccountTranslation;
CREATE TABLE rpt.AccountTranslation (
    AccountKey    int           NOT NULL PRIMARY KEY,
    AccountNameAR nvarchar(100) NOT NULL
);

INSERT INTO rpt.AccountTranslation (AccountKey, AccountNameAR) VALUES
-- Totals
(47,  N'صافي الربح'),
(48,  N'الربح التشغيلي'),
(49,  N'مجمل الربح'),
-- Revenue
(50,  N'صافي المبيعات'),
(51,  N'إجمالي المبيعات'),
(101, N'المبيعات التجارية'),
(52,  N'المبيعات بين شركات المجموعة'),
(53,  N'المردودات والتسويات'),
(54,  N'الخصومات المسموح بها'),
-- Cost of sales
(55,  N'تكلفة المبيعات'),
(56,  N'التكلفة المعيارية للمبيعات'),
(57,  N'انحرافات التكلفة'),
-- Operating expenses
(58,  N'المصاريف التشغيلية'),
(59,  N'تكاليف الموظفين'),
(60,  N'الرواتب والأجور'),
(61,  N'ضرائب الرواتب'),
(62,  N'مزايا الموظفين'),
(63,  N'العمولات'),
(64,  N'مصاريف السفر'),
(65,  N'مواصلات السفر'),
(66,  N'الإقامة والفنادق'),
(67,  N'الوجبات'),
(68,  N'الضيافة'),
(69,  N'مصاريف سفر أخرى'),
(70,  N'التسويق'),
(71,  N'المؤتمرات والمعارض'),
(72,  N'المواد الدعائية'),
(73,  N'اللوازم المكتبية'),
(74,  N'الأتعاب المهنية'),
(75,  N'الاتصالات والمرافق'),
(76,  N'الهاتف والاتصالات'),
(77,  N'الكهرباء والمياه'),
(78,  N'مصاريف أخرى'),
(79,  N'الإهلاك والإطفاء'),
(80,  N'إهلاك تحسينات المباني المستأجرة'),
(81,  N'إهلاك المركبات'),
(82,  N'إهلاك المعدات'),
(83,  N'إهلاك الأثاث والتجهيزات'),
(84,  N'إهلاك أصول أخرى'),
(85,  N'إطفاء الشهرة'),
(87,  N'الإيجار'),
-- Other income & expense
(88,  N'إيرادات ومصاريف أخرى'),
(89,  N'إيرادات الفوائد'),
(90,  N'مصروف الفوائد'),
(91,  N'أرباح (خسائر) بيع الأصول'),
(92,  N'إيرادات أخرى'),
(93,  N'أرباح (خسائر) فروق العملة'),
-- Taxes
(94,  N'ضريبة الدخل');

-- ---------------------------------------------
-- 2) Departments
-- ---------------------------------------------
DROP TABLE IF EXISTS rpt.DepartmentTranslation;
CREATE TABLE rpt.DepartmentTranslation (
    DepartmentGroupKey int           NOT NULL PRIMARY KEY,
    DepartmentNameAR   nvarchar(100) NOT NULL
);

INSERT INTO rpt.DepartmentTranslation (DepartmentGroupKey, DepartmentNameAR) VALUES
(1, N'الشركة (إجمالي)'),
(2, N'الإدارة العامة والتنفيذية'),
(3, N'إدارة المخزون'),
(4, N'التصنيع'),
(5, N'ضمان الجودة'),
(6, N'البحث والتطوير'),
(7, N'المبيعات والتسويق');

-- ---------------------------------------------
-- 3) Scenarios (matched by name, not key)
-- ---------------------------------------------
DROP TABLE IF EXISTS rpt.ScenarioTranslation;
CREATE TABLE rpt.ScenarioTranslation (
    ScenarioName   nvarchar(50)  NOT NULL PRIMARY KEY,
    ScenarioNameAR nvarchar(50)  NOT NULL
);

INSERT INTO rpt.ScenarioTranslation (ScenarioName, ScenarioNameAR) VALUES
(N'Actual',   N'الفعلي'),
(N'Budget',   N'الموازنة'),
(N'Forecast', N'التوقعات');

-- ---------------------------------------------
-- 4) Organizations (branches)
-- ---------------------------------------------
DROP TABLE IF EXISTS rpt.OrganizationTranslation;
CREATE TABLE rpt.OrganizationTranslation (
    OrganizationKey    int           NOT NULL PRIMARY KEY,
    OrganizationNameAR nvarchar(100) NOT NULL
);

INSERT INTO rpt.OrganizationTranslation (OrganizationKey, OrganizationNameAR) VALUES
(1,  N'مجموعة أدفنتشر ووركس'),
(2,  N'عمليات أمريكا الشمالية'),
(14, N'عمليات الولايات المتحدة'),
(3,  N'القطاع الشمالي الشرقي'),
(4,  N'القطاع الشمالي الغربي'),
(5,  N'القطاع الأوسط'),
(6,  N'القطاع الجنوبي الشرقي'),
(7,  N'القطاع الجنوبي الغربي'),
(8,  N'قطاع كندا'),
(9,  N'العمليات الأوروبية'),
(11, N'فرنسا'),
(12, N'ألمانيا'),
(10, N'عمليات آسيا والمحيط الهادئ'),
(13, N'أستراليا');
GO

-- ---------------------------------------------
-- (Check) Every Income Statement account must have an Arabic name
--         Expected: 0 rows
-- ---------------------------------------------
WITH IncomeTree AS (
    SELECT AccountKey FROM dbo.DimAccount
    WHERE  ParentAccountKey IS NULL AND AccountDescription = N'Net Income'
    UNION ALL
    SELECT c.AccountKey FROM dbo.DimAccount c
    JOIN   IncomeTree t ON c.ParentAccountKey = t.AccountKey
)
SELECT  a.AccountKey, a.AccountDescription AS MissingTranslation
FROM    IncomeTree it
JOIN    dbo.DimAccount a ON a.AccountKey = it.AccountKey
LEFT JOIN rpt.AccountTranslation tr ON tr.AccountKey = it.AccountKey
WHERE   tr.AccountKey IS NULL;

-- (Review) English vs Arabic side by side
SELECT  a.AccountKey, a.AccountDescription AS AccountNameEN, tr.AccountNameAR
FROM    rpt.AccountTranslation tr
JOIN    dbo.DimAccount a ON a.AccountKey = tr.AccountKey
ORDER BY a.AccountCodeAlternateKey;
