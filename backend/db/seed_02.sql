CREATE OR REPLACE FUNCTION h(t text) RETURNS bigint LANGUAGE sql IMMUTABLE
AS $$ SELECT abs(hashtext(t)::bigint) $$;

ALTER TABLE accounts  ADD COLUMN IF NOT EXISTS national_id text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS national_id text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS subject_ref text;
CREATE UNIQUE INDEX IF NOT EXISTS customers_org_nid ON customers (org, national_id);
CREATE INDEX IF NOT EXISTS customers_subject_ref ON customers (subject_ref);

BEGIN;
TRUNCATE accounts, customers;

INSERT INTO accounts (account_id, org, national_id)
SELECT u.account_id, m.org, 'SYN-' || substr(md5(u.account_id), 1, 12)
FROM (SELECT from_account AS account_id FROM transactions
      UNION
      SELECT to_account FROM transactions) u
JOIN bank_map m ON m.source_bank = split_part(u.account_id, ':', 1)::int;

-- 300 people who bank at both institutions: Bank B's account takes Bank A's identity
WITH a AS (SELECT national_id, row_number() OVER (ORDER BY md5(account_id || 'p')) AS rn
           FROM accounts WHERE org = 'Org1MSP'),
     b AS (SELECT account_id, row_number() OVER (ORDER BY md5(account_id || 'q')) AS rn
           FROM accounts WHERE org = 'Org2MSP'),
     p AS (SELECT a.national_id, b.account_id AS b_id FROM a JOIN b USING (rn) WHERE rn <= 300)
UPDATE accounts x SET national_id = p.national_id FROM p WHERE x.account_id = p.b_id;

INSERT INTO customers (org, full_name, national_id, kyc_status, risk_tier, onboarded_at)
SELECT d.org,
  (ARRAY['Aarav','Vihaan','Aditya','Arjun','Rohan','Karthik','Sanjay','Ravi','Vikram','Suresh',
         'Ananya','Priya','Divya','Meera','Lakshmi','Kavya','Nisha','Pooja','Revathi','Sneha'])
    [1 + h(d.national_id) % 20]
  || ' ' ||
  (ARRAY['Kumar','Sharma','Iyer','Nair','Reddy','Pillai','Menon','Gupta','Das','Rao',
         'Singh','Patel','Joshi','Mehta','Krishnan','Subramanian','Naidu','Verma','Bose','Chopra'])
    [1 + h(d.national_id || 'l') % 20],
  d.national_id,
  CASE WHEN h(d.national_id || d.org || 'k') % 100 < 92 THEN 'VERIFIED'
       WHEN h(d.national_id || d.org || 'k') % 100 < 97 THEN 'PENDING_REVIEW'
       ELSE 'EXPIRED' END,
  CASE WHEN d.org = 'Org1MSP' THEN   -- Bank A: riskier customer mix than Bank B
         CASE WHEN h(d.national_id || d.org || 'r') % 100 < 78 THEN 'LOW'
              WHEN h(d.national_id || d.org || 'r') % 100 < 93 THEN 'MEDIUM' ELSE 'HIGH' END
       ELSE
         CASE WHEN h(d.national_id || d.org || 'r') % 100 < 86 THEN 'LOW'
              WHEN h(d.national_id || d.org || 'r') % 100 < 96 THEN 'MEDIUM' ELSE 'HIGH' END
  END,
  DATE '2015-01-01' + (h(d.national_id || d.org || 'd') % 2700)::int
FROM (SELECT DISTINCT org, national_id FROM accounts) d;

UPDATE accounts a SET customer_id = c.customer_id
FROM customers c WHERE c.org = a.org AND c.national_id = a.national_id;
COMMIT;

CREATE INDEX IF NOT EXISTS accounts_customer ON accounts (customer_id);
ANALYZE accounts; ANALYZE customers;