const crypto = require('crypto');

function canonicalize(v) {
  if (v === undefined || v === null) return 'null';
  if (Array.isArray(v)) return '[' + v.map(canonicalize).join(',') + ']';
  if (typeof v === 'object')
    return '{' + Object.keys(v).sort()
      .map(k => JSON.stringify(k) + ':' + canonicalize(v[k])).join(',') + '}';
  return JSON.stringify(v);
}

const sha256 = s => crypto.createHash('sha256').update(s).digest('hex');
const contextHash = obj => sha256(canonicalize(obj));
const subjectRef = (id, secret) =>
  crypto.createHmac('sha256', secret).update(String(id)).digest('hex');

module.exports = { canonicalize, contextHash, subjectRef };
