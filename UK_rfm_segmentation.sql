-- Step 1: Create and set up Database
CREATE DATABASE IF NOT EXISTS uk_retail;
USE uk_retail;

-- Drop table if it already exists to ensure a clean setup
DROP TABLE IF EXISTS retail_transactions;

-- Step 2: Create raw schema with VARCHAR types for seamless bulk import
CREATE TABLE retail_transactions (
    InvoiceNo VARCHAR(50),
    StockCode VARCHAR(50),
    Description VARCHAR(255),
    Quantity VARCHAR(50),
    InvoiceDate VARCHAR(50),
    UnitPrice VARCHAR(50),
    CustomerID VARCHAR(50),
    Country VARCHAR(50),
    TotalSpend VARCHAR(50)
);

-- Step 3: Fast Bulk Data Load via LOAD DATA LOCAL INFILE
-- Note: Replace file path with your local CSV directory
SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'C:/path/to/Online_Retail_Cleaned.csv'
INTO TABLE retail_transactions
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country, TotalSpend);

-- Step 4: Sanitize Data Types & Calculate Spend
-- Disable strict mode temporarily to avoid decimal/blank conversion warnings
SET SESSION sql_mode = '';

-- Replace invalid/blank values with NULLs
UPDATE retail_transactions 
SET 
    Quantity = CASE WHEN TRIM(Quantity) REGEXP '^-?[0-9]+$' THEN TRIM(Quantity) ELSE NULL END,
    UnitPrice = CASE WHEN TRIM(UnitPrice) REGEXP '^-?[0-9]+(\.[0-9]+)?$' THEN TRIM(UnitPrice) ELSE NULL END,
    CustomerID = CASE WHEN TRIM(CustomerID) REGEXP '^[0-9]+$' THEN TRIM(CustomerID) ELSE NULL END,
    TotalSpend = CASE WHEN TRIM(TotalSpend) REGEXP '^-?[0-9]+(\.[0-9]+)?$' THEN TRIM(TotalSpend) ELSE NULL END;

-- Alter table columns to their optimal data types
ALTER TABLE retail_transactions 
MODIFY COLUMN Quantity INT,
MODIFY COLUMN InvoiceDate DATETIME,
MODIFY COLUMN UnitPrice DECIMAL(10,2),
MODIFY COLUMN CustomerID INT,
MODIFY COLUMN TotalSpend DECIMAL(10,2);

-- Compute TotalSpend for accuracy
UPDATE retail_transactions 
SET TotalSpend = Quantity * UnitPrice;

-- Step 5: Execute RFM Segmentation Query
-- Reference Date set to '2011-12-10' (1 day after max dataset date)
WITH customer_rfm_raw AS (
    SELECT 
        CustomerID,
        DATEDIFF('2011-12-10', MAX(InvoiceDate)) AS recency,
        COUNT(DISTINCT InvoiceNo) AS frequency,
        ROUND(SUM(TotalSpend), 2) AS monetary
    FROM retail_transactions
    WHERE CustomerID IS NOT NULL AND CustomerID != 0
    GROUP BY CustomerID
),
rfm_scores AS (
    SELECT 
        CustomerID,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_rfm_raw
)
SELECT 
    CustomerID,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_cell,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'Recent / Promising'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk / Can\'t Lose'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost Customers'
        ELSE 'Needs Attention'
    END AS customer_segment
FROM rfm_scores
ORDER BY monetary DESC;