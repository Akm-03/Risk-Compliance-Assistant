BEGIN;
TRUNCATE transactions RESTART IDENTITY;
TRUNCATE bank_map;
TRUNCATE eval.ground_truth;

INSERT INTO bank_map (source_bank, org)
SELECT bank,
       CASE WHEN row_number() OVER (ORDER BY vol DESC, bank) % 2 = 0 THEN 'Org2MSP' ELSE 'Org1MSP' END
FROM (
  SELECT bank, count(*) AS vol
  FROM (SELECT from_bank AS bank FROM eval.raw_tx
        UNION ALL
        SELECT to_bank FROM eval.raw_tx) u
  GROUP BY bank
) b;

INSERT INTO transactions (src_row_id, ts, from_account, to_account, from_org, to_org,
  amount_paid, currency_paid, amount_received, currency_received, pay_format)
SELECT r.row_id, to_timestamp(r.ts, 'YYYY/MM/DD HH24:MI'),
       r.from_bank || ':' || r.from_acct, r.to_bank || ':' || r.to_acct, f.org, t.org,
       r.amt_paid, r.cur_paid, r.amt_received, r.cur_received, r.pay_format
FROM eval.raw_tx r
JOIN bank_map f ON f.source_bank = r.from_bank
JOIN bank_map t ON t.source_bank = r.to_bank
WHERE r.ts >= '2022/09/01' AND r.ts < '2022/09/03'
ORDER BY 2, 1;

INSERT INTO eval.ground_truth (tx_id, is_laundering)
SELECT t.tx_id, r.is_laundering = 1
FROM transactions t JOIN eval.raw_tx r ON r.row_id = t.src_row_id;
COMMIT;

CREATE INDEX IF NOT EXISTS tx_ts ON transactions (ts);
CREATE INDEX IF NOT EXISTS tx_from_ts ON transactions (from_account, ts);
CREATE INDEX IF NOT EXISTS tx_to_ts ON transactions (to_account, ts);
CREATE INDEX IF NOT EXISTS accounts_customer ON accounts (customer_id);
ANALYZE;