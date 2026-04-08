-- ============================================================
-- FUNCTION: fn_parse_any_date
-- PURPOSE:  Accept any common date format as VARCHAR and
--           return a proper MySQL DATE (YYYY-MM-DD).
-- USAGE:    SELECT fn_parse_any_date('2021-06-29T20:00:00.000-04:00');
--           → 2021-06-29
-- ============================================================

DELIMITER $$

DROP FUNCTION IF EXISTS fn_parse_any_date$$

CREATE FUNCTION fn_parse_any_date(raw_date VARCHAR(100))
RETURNS DATE
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_trimmed  VARCHAR(100);
    DECLARE v_cleaned  VARCHAR(100);
    DECLARE v_format   VARCHAR(50);
    DECLARE v_result   DATE;

    -- Step 0: Trim whitespace
    SET v_trimmed = TRIM(raw_date);

    -- Return NULL for empty/null input
    IF v_trimmed IS NULL OR v_trimmed = '' THEN
        RETURN NULL;
    END IF;

    -- =========================================================
    -- STEP 1: Preprocess / Normalize special formats
    -- =========================================================

    -- ISO 8601 with T separator (handles T, millis, TZ offset, Z)
    -- e.g. 2021-06-29T20:00:00.000-04:00 → 2021-06-29 20:00:00
    IF v_trimmed REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' THEN
        SET v_cleaned = REPLACE(SUBSTRING(v_trimmed, 1, 19), 'T', ' ');
        SET v_format  = '%Y-%m-%d %H:%i:%s';

    -- Unix timestamp in milliseconds (13 digits)
    ELSEIF v_trimmed REGEXP '^[0-9]{13}$' THEN
        RETURN DATE(FROM_UNIXTIME(CAST(v_trimmed AS UNSIGNED) / 1000));

    -- Unix timestamp in seconds (10 digits)
    ELSEIF v_trimmed REGEXP '^[0-9]{10}$' THEN
        RETURN DATE(FROM_UNIXTIME(CAST(v_trimmed AS UNSIGNED)));

    -- Day name prefix: "Tuesday, April 8, 2025" → "April 8, 2025"
    ELSEIF v_trimmed REGEXP '^[A-Za-z]+day,? ' THEN
        SET v_cleaned = REGEXP_REPLACE(v_trimmed, '^[A-Za-z]+day,?\\s+', '');
        SET v_format  = '%M %d, %Y';

    -- Ordinal suffix: "8th April 2025" → "8 April 2025"
    ELSEIF v_trimmed REGEXP '[0-9](st|nd|rd|th) ' THEN
        SET v_cleaned = REGEXP_REPLACE(v_trimmed, '(st|nd|rd|th)', '');
        SET v_format  = '%d %M %Y';

    -- =========================================================
    -- STEP 2: Standard format detection (most specific first)
    -- =========================================================

    -- yyyy-mm-dd HH:mm:ss
    ELSEIF v_trimmed REGEXP '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y-%m-%d %H:%i:%s';

    -- yyyy-mm-dd HH:mm (no seconds)
    ELSEIF v_trimmed REGEXP '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} [0-9]{1,2}:[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y-%m-%d %H:%i';

    -- yyyy-mm-dd
    ELSEIF v_trimmed REGEXP '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y-%m-%d';

    -- yyyy/mm/dd
    ELSEIF v_trimmed REGEXP '^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y/%m/%d';

    -- yyyy.mm.dd
    ELSEIF v_trimmed REGEXP '^[0-9]{4}\\.[0-9]{1,2}\\.[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y.%m.%d';

    -- mm/dd/yyyy HH:mm:ss
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%m/%d/%Y %H:%i:%s';

    -- mm/dd/yyyy hh:mm:ss AM/PM
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [APap][Mm]$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%m/%d/%Y %h:%i:%s %p';

    -- mm/dd/yyyy
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%m/%d/%Y';

    -- mm/dd/yy
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%m/%d/%y';

    -- dd.mm.yyyy
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d.%m.%Y';

    -- dd.mm.yy
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d.%m.%y';

    -- dd-mm-yyyy
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d-%m-%Y';

    -- dd-Mon-yyyy (08-Apr-2025)
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d-%b-%Y';

    -- dd-Mon-yy (08-Apr-25)
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d-%b-%y';

    -- yyyymmdd (compact)
    ELSEIF v_trimmed REGEXP '^[0-9]{8}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%Y%m%d';

    -- dd Month yyyy / dd Mon yyyy (8 April 2025)
    ELSEIF v_trimmed REGEXP '^[0-9]{1,2} [A-Za-z]+ [0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%d %M %Y';

    -- Month dd, yyyy / Mon dd, yyyy (April 8, 2025)
    ELSEIF v_trimmed REGEXP '^[A-Za-z]+ [0-9]{1,2},? [0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%M %d, %Y';

    -- Month yyyy (Apr 2025 → defaults to 1st of month)
    ELSEIF v_trimmed REGEXP '^[A-Za-z]+ [0-9]{4}$' THEN
        SET v_cleaned = v_trimmed;
        SET v_format  = '%M %Y';

    -- Unrecognized format → return NULL
    ELSE
        RETURN NULL;
    END IF;

    -- =========================================================
    -- STEP 3: Parse and return as DATE (YYYY-MM-DD)
    -- =========================================================
    SET v_result = DATE(STR_TO_DATE(v_cleaned, v_format));

    RETURN v_result;

END$$

DELIMITER ;


-- ============================================================
--                    USAGE EXAMPLES
-- ============================================================

-- -------------------------------------------------------
-- 1. BASIC: Parse a single value
-- -------------------------------------------------------
SELECT fn_parse_any_date('2021-06-29T20:00:00.000-04:00') AS parsed_date;
-- Result: 2021-06-29


-- -------------------------------------------------------
-- 2. SELECT: Clean a column in a query
-- -------------------------------------------------------
SELECT
    id,
    P_END_DATE,
    fn_parse_any_date(P_END_DATE)   AS clean_end_date,
    P_START_DATE,
    fn_parse_any_date(P_START_DATE) AS clean_start_date
FROM your_table;


-- -------------------------------------------------------
-- 3. WHERE: Filter using the parsed date
-- -------------------------------------------------------
SELECT *
FROM your_table
WHERE fn_parse_any_date(P_START_DATE) >= '2020-01-01'
  AND fn_parse_any_date(P_END_DATE)   <= '2025-12-31';


-- -------------------------------------------------------
-- 4. INSERT: Clean messy data into a proper table
-- -------------------------------------------------------
INSERT INTO clean_table (id, start_date, end_date)
SELECT
    id,
    fn_parse_any_date(P_START_DATE),
    fn_parse_any_date(P_END_DATE)
FROM staging_table;


-- -------------------------------------------------------
-- 5. UPDATE: Fix existing messy dates in-place
-- -------------------------------------------------------
UPDATE your_table
SET proper_date = fn_parse_any_date(raw_date_string)
WHERE proper_date IS NULL;


-- -------------------------------------------------------
-- 6. CALCULATED COLUMNS: Date difference
-- -------------------------------------------------------
SELECT
    id,
    DATEDIFF(
        fn_parse_any_date(P_END_DATE),
        fn_parse_any_date(P_START_DATE)
    ) AS days_between
FROM your_table;


-- -------------------------------------------------------
-- 7. TEST: Verify all 27 supported formats
-- -------------------------------------------------------
SELECT input_val, fn_parse_any_date(input_val) AS parsed
FROM (
    SELECT '2025-04-08'                        AS input_val UNION ALL  -- ISO
    SELECT '04/08/2025'                                     UNION ALL  -- US slash
    SELECT '04/08/25'                                       UNION ALL  -- US slash short
    SELECT '08.04.2025'                                     UNION ALL  -- EU dot
    SELECT '08.04.25'                                       UNION ALL  -- EU dot short
    SELECT '08-04-2025'                                     UNION ALL  -- EU dash
    SELECT '08-Apr-2025'                                    UNION ALL  -- dd-Mon-yyyy
    SELECT '08-Apr-25'                                      UNION ALL  -- dd-Mon-yy
    SELECT '20250408'                                       UNION ALL  -- compact
    SELECT '8 April 2025'                                   UNION ALL  -- dd Month yyyy
    SELECT 'April 8, 2025'                                  UNION ALL  -- Month dd, yyyy
    SELECT 'Apr 8, 2025'                                    UNION ALL  -- Mon dd, yyyy
    SELECT '2025/04/08'                                     UNION ALL  -- yyyy/mm/dd
    SELECT '2025.04.08'                                     UNION ALL  -- yyyy.mm.dd
    SELECT '2025-04-08 14:30:00'                            UNION ALL  -- datetime
    SELECT '2025-04-08 14:30'                               UNION ALL  -- datetime no sec
    SELECT '2025-04-08T14:30:00'                            UNION ALL  -- ISO T
    SELECT '2025-04-08T14:30:00.000-04:00'                  UNION ALL  -- ISO T + TZ
    SELECT '2025-04-08T14:30:00Z'                           UNION ALL  -- ISO T + Z
    SELECT '2021-06-29T20:00:00.000-04:00'                  UNION ALL  -- your data
    SELECT '2020-12-31T19:00:00.000-05:00'                  UNION ALL  -- your data
    SELECT '04/08/2025 14:30:00'                            UNION ALL  -- US + time
    SELECT '04/08/2025 02:30:00 PM'                         UNION ALL  -- US + AM/PM
    SELECT 'Tuesday, April 8, 2025'                         UNION ALL  -- day name
    SELECT '8th April 2025'                                 UNION ALL  -- ordinal
    SELECT 'April 2025'                                     UNION ALL  -- month-year
    SELECT '1744108200'                                     UNION ALL  -- unix sec
    SELECT '1744108200000'                                             -- unix millis
) AS test_data;

/*
  EXPECTED OUTPUT:
  +--------------------------------------+------------+
  | input_val                            | parsed     |
  +--------------------------------------+------------+
  | 2025-04-08                           | 2025-04-08 |
  | 04/08/2025                           | 2025-04-08 |
  | 04/08/25                             | 2025-04-08 |
  | 08.04.2025                           | 2025-04-08 |
  | 08.04.25                             | 2025-04-08 |
  | 08-04-2025                           | 2025-04-08 |
  | 08-Apr-2025                          | 2025-04-08 |
  | 08-Apr-25                            | 2025-04-08 |
  | 20250408                             | 2025-04-08 |
  | 8 April 2025                         | 2025-04-08 |
  | April 8, 2025                        | 2025-04-08 |
  | Apr 8, 2025                          | 2025-04-08 |
  | 2025/04/08                           | 2025-04-08 |
  | 2025.04.08                           | 2025-04-08 |
  | 2025-04-08 14:30:00                  | 2025-04-08 |
  | 2025-04-08 14:30                     | 2025-04-08 |
  | 2025-04-08T14:30:00                  | 2025-04-08 |
  | 2025-04-08T14:30:00.000-04:00        | 2025-04-08 |
  | 2025-04-08T14:30:00Z                 | 2025-04-08 |
  | 2021-06-29T20:00:00.000-04:00        | 2021-06-29 |
  | 2020-12-31T19:00:00.000-05:00        | 2020-12-31 |
  | 04/08/2025 14:30:00                  | 2025-04-08 |
  | 04/08/2025 02:30:00 PM               | 2025-04-08 |
  | Tuesday, April 8, 2025               | 2025-04-08 |
  | 8th April 2025                       | 2025-04-08 |
  | April 2025                           | 2025-04-01 |
  | 1744108200                           | 2025-04-08 |
  | 1744108200000                        | 2025-04-08 |
  +--------------------------------------+------------+
*/
