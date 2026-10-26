'use strict';
const { Contract } = require('fabric-contract-api');

const EVENT_TYPES = new Set(['AML_DECISION', 'KYC_VERIFICATION', 'KYC_REVOCATION', 'TYPOLOGY_ALERT']);
const MODEL_GATED = new Set(['AML_DECISION', 'KYC_VERIFICATION', 'KYC_REVOCATION']);
const MSP_ROLE = { Org1MSP: 'BANK_A', Org2MSP: 'BANK_B', Org3MSP: 'REGULATOR' };
const HEX64 = /^[a-f0-9]{64}$/;

const need = (cond, msg) => { if (!cond) throw new Error(msg); };
const evKey = (id) => `EVT_${id}`;

// Deterministic time: taken from the transaction, never from Date.now()
function txTime(ctx) {
  const t = ctx.stub.getTxTimestamp();
  let s = t.seconds;
  if (s && typeof s.toNumber === 'function') s = s.toNumber();
  else if (s && typeof s === 'object') s = s.low;
  return new Date(Number(s) * 1000 + Math.floor(Number(t.nanos || 0) / 1e6)).toISOString();
}

class AriaContract extends Contract {
  constructor() { super('AriaContract'); }

  // ---------- model registry (regulator only) ----------
  async RegisterModel(ctx, modelVersion, promptVersion, descriptionHash) {
    const msp = ctx.clientIdentity.getMSPID();
    need(MSP_ROLE[msp] === 'REGULATOR', 'Only the regulator may register models');
    need(HEX64.test(descriptionHash), 'descriptionHash must be 64 hex chars');
    const key = ctx.stub.createCompositeKey('model', [modelVersion, promptVersion]);
    const ex = await ctx.stub.getState(key);
    need(!ex || ex.length === 0, 'Model/prompt pair already registered');
    const rec = {
      modelVersion, promptVersion, descriptionHash,
      status: 'APPROVED', registeredBy: msp, registeredAt: txTime(ctx),
    };
    await ctx.stub.putState(key, Buffer.from(JSON.stringify(rec)));
    return JSON.stringify(rec);
  }

  async RevokeModel(ctx, modelVersion, promptVersion) {
    need(MSP_ROLE[ctx.clientIdentity.getMSPID()] === 'REGULATOR', 'Only the regulator may revoke models');
    const key = ctx.stub.createCompositeKey('model', [modelVersion, promptVersion]);
    const b = await ctx.stub.getState(key);
    need(b && b.length > 0, 'Model/prompt pair not found');
    const rec = JSON.parse(b.toString());
    rec.status = 'REVOKED';
    rec.revokedAt = txTime(ctx);
    await ctx.stub.putState(key, Buffer.from(JSON.stringify(rec)));
    return JSON.stringify(rec);
  }

  async GetModel(ctx, modelVersion, promptVersion) {
    const key = ctx.stub.createCompositeKey('model', [modelVersion, promptVersion]);
    const b = await ctx.stub.getState(key);
    need(b && b.length > 0, 'Model/prompt pair not found');
    return b.toString();
  }

  // ---------- compliance events ----------
  async LogComplianceEvent(ctx, eventJson) {
    let e;
    try { e = JSON.parse(eventJson); } catch (_) { throw new Error('eventJson is not valid JSON'); }

    need(e.schemaVersion === 1, 'Unsupported schemaVersion');
    need(/^[A-Za-z0-9-]{8,64}$/.test(e.eventId || ''), 'Bad eventId');
    need(EVENT_TYPES.has(e.eventType), 'Bad eventType');
    need(HEX64.test(e.subjectRef || ''), 'subjectRef must be a 64-hex HMAC');
    need(HEX64.test(e.recordHash || ''), 'recordHash must be 64 hex chars');
    need(HEX64.test(e.contextHash || ''), 'contextHash must be 64 hex chars');
    need(typeof e.decision === 'string' && e.decision.length > 0 && e.decision.length <= 32, 'Bad decision');

    // Identity comes from the signed proposal, never from the payload
    const msp = ctx.clientIdentity.getMSPID();
    const role = MSP_ROLE[msp];
    need(role, 'Unknown organisation');
    need(role !== 'REGULATOR' || e.eventType === 'TYPOLOGY_ALERT', 'Regulator may only log typology alerts');

    if (MODEL_GATED.has(e.eventType)) {
      need(e.modelVersion && e.promptVersion, 'modelVersion and promptVersion are required');
      const mk = ctx.stub.createCompositeKey('model', [e.modelVersion, e.promptVersion]);
      const mb = await ctx.stub.getState(mk);
      need(mb && mb.length > 0, 'Model/prompt pair is not registered');
      need(JSON.parse(mb.toString()).status === 'APPROVED', 'Model/prompt pair is not approved');
    }

    const key = evKey(e.eventId);
    const ex = await ctx.stub.getState(key);
    need(!ex || ex.length === 0, 'eventId already exists');

    const rec = {
      schemaVersion: 1,
      eventId: e.eventId,
      eventType: e.eventType,
      orgId: msp,
      orgRole: role,
      subjectRef: e.subjectRef,
      decision: e.decision,
      riskBand: e.riskBand || null,
      recordHash: e.recordHash,
      contextHash: e.contextHash,
      modelVersion: e.modelVersion || null,
      promptVersion: e.promptVersion || null,
      humanReview: {
        status: e.eventType === 'TYPOLOGY_ALERT' ? 'NOT_REQUIRED' : 'PENDING',
        reviewerRef: null,
        reviewedAt: null,
      },
      createdAt: txTime(ctx),
    };

    await ctx.stub.putState(key, Buffer.from(JSON.stringify(rec)));
    // index so any bank can look up everything known about a subject
    const idx = ctx.stub.createCompositeKey('subject~event', [rec.subjectRef, rec.eventId]);
    await ctx.stub.putState(idx, Buffer.from('\u0000'));
    ctx.stub.setEvent('ComplianceEventLogged', Buffer.from(JSON.stringify({
      eventId: rec.eventId, eventType: rec.eventType, orgId: rec.orgId, subjectRef: rec.subjectRef,
    })));
    return JSON.stringify(rec);
  }

  async RecordHumanReview(ctx, eventId, status, reviewerRef) {
    need(['CONFIRMED', 'OVERRIDDEN'].includes(status), 'status must be CONFIRMED or OVERRIDDEN');
    need(HEX64.test(reviewerRef), 'reviewerRef must be a 64-hex HMAC');
    const rec = await this._load(ctx, eventId);
    need(ctx.clientIdentity.getMSPID() === rec.orgId, 'Only the originating organisation may review');
    need(rec.humanReview.status === 'PENDING', 'Event is not pending review');
    rec.humanReview = { status, reviewerRef, reviewedAt: txTime(ctx) };
    await ctx.stub.putState(evKey(eventId), Buffer.from(JSON.stringify(rec)));
    return JSON.stringify(rec);
  }

  // ---------- reads ----------
  async GetEvent(ctx, eventId) {
    return JSON.stringify(await this._load(ctx, eventId));
  }

  // every state this event has been in (creation, then review)
  async GetEventHistory(ctx, eventId) {
    const it = await ctx.stub.getHistoryForKey(evKey(eventId));
    const out = [];
    let r = await it.next();
    while (!r.done) {
      out.push({ txId: r.value.txId, isDelete: r.value.isDelete, value: JSON.parse(r.value.value.toString()) });
      r = await it.next();
    }
    await it.close();
    return JSON.stringify(out);
  }

  // cross-bank intelligence: what does the consortium know about this subject?
  async GetEventsBySubject(ctx, subjectRef) {
    const it = await ctx.stub.getStateByPartialCompositeKey('subject~event', [subjectRef]);
    const out = [];
    let r = await it.next();
    while (!r.done) {
      const { attributes } = ctx.stub.splitCompositeKey(r.value.key);
      const b = await ctx.stub.getState(evKey(attributes[1]));
      if (b && b.length > 0) out.push(JSON.parse(b.toString()));
      r = await it.next();
    }
    await it.close();
    return JSON.stringify(out);
  }

  // methods starting with "_" are not callable as transactions
  async _load(ctx, eventId) {
    const b = await ctx.stub.getState(evKey(eventId));
    need(b && b.length > 0, `Event ${eventId} not found`);
    return JSON.parse(b.toString());
  }
}

module.exports = AriaContract;