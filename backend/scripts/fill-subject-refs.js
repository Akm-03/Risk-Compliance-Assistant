const { Pool } = require('pg');
const { subjectRef } = require('../src/lib/hashing');

const secret = process.env.SUBJECT_REF_SECRET;
if (!secret) { console.error('SUBJECT_REF_SECRET is not set'); process.exit(1); }

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://aria:aria@localhost:5432/aria',
});
const BATCH = 5000;

(async () => {
  let done = 0;
  for (;;) {
    const { rows } = await pool.query(
      `SELECT customer_id FROM customers
       WHERE subject_ref IS NULL ORDER BY customer_id LIMIT $1`, [BATCH]);
    if (!rows.length) break;
    await pool.query(
      `UPDATE customers c SET subject_ref = v.ref
       FROM unnest($1::uuid[], $2::text[]) AS v(id, ref)
       WHERE c.customer_id = v.id`,
      [rows.map(r => r.customer_id), rows.map(r => subjectRef(r.customer_id, secret))]);
    done += rows.length;
    console.log(`filled ${done}`);
  }
  const { rows: [c] } = await pool.query(
    `SELECT count(*)::int total, count(subject_ref)::int filled,
            count(DISTINCT subject_ref)::int distinct_refs FROM customers`);
  console.log(c);
  await pool.end();
  if (c.total !== c.filled || c.total !== c.distinct_refs) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
