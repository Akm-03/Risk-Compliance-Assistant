CREATE SCHEMA eval;   -- labels and raw data live here; the app role never gets access

CREATE TABLE eval.raw_tx (
  row_id bigserial PRIMARY KEY,
  ts text, from_bank int, from_acct text, to_bank int, to_acct text,
  amt_received numeric, cur_received text, amt_paid numeric, cur_paid text,
  pay_format text, is_laundering smallint
);
CREATE TABLE eval.ground_truth (tx_id bigint PRIMARY KEY, is_laundering boolean NOT NULL);

CREATE TABLE bank_map (
  source_bank int PRIMARY KEY,
  org text NOT NULL CHECK (org IN ('Org1MSP','Org2MSP'))
);

CREATE TABLE customers (
  customer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org text NOT NULL, full_name text NOT NULL, national_id text, subject_ref text,
  kyc_status text NOT NULL DEFAULT 'VERIFIED', risk_tier text NOT NULL DEFAULT 'LOW',
  onboarded_at date NOT NULL
);
CREATE UNIQUE INDEX customers_org_nid ON customers (org, national_id);
CREATE INDEX customers_subject_ref ON customers (subject_ref);

CREATE TABLE accounts (
  account_id text PRIMARY KEY, org text NOT NULL, national_id text,
  customer_id uuid REFERENCES customers
);

CREATE TABLE transactions (
  tx_id bigserial PRIMARY KEY, src_row_id bigint, ts timestamptz NOT NULL,
  from_account text NOT NULL, to_account text NOT NULL,
  from_org text NOT NULL, to_org text NOT NULL,
  amount_paid numeric NOT NULL, currency_paid text NOT NULL,
  amount_received numeric NOT NULL, currency_received text NOT NULL,
  pay_format text NOT NULL, status text NOT NULL DEFAULT 'NEW'
);

CREATE TABLE cases (
  case_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type text NOT NULL, org text NOT NULL, subject_ref text NOT NULL,
  tx_ids bigint[] NOT NULL, tier1_features jsonb NOT NULL,
  agent_output jsonb, model_version text, prompt_version text,
  context_hash text, record_hash text, chain_tx_id text,
  review_status text NOT NULL DEFAULT 'PENDING', created_at timestamptz NOT NULL DEFAULT now()
);

CREATE ROLE aria_app  LOGIN PASSWORD 'change_me_app';
CREATE ROLE aria_eval LOGIN PASSWORD 'change_me_eval';
GRANT USAGE ON SCHEMA public TO aria_app, aria_eval;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO aria_app, aria_eval;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO aria_app, aria_eval;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO aria_app, aria_eval;
GRANT USAGE ON SCHEMA eval TO aria_eval;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA eval TO aria_eval;