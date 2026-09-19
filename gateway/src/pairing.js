import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

const ticketLifetimeMs = 2 * 60 * 1000;
const maximumTickets = 16;

function digest(value) {
  return createHash('sha256').update(value).digest('base64url');
}

function signature(masterToken, deviceId) {
  return createHmac('sha256', masterToken).update(`device:${deviceId}`).digest('base64url');
}

export class PairingAuthority {
  constructor(username, masterToken, { now = () => Date.now(), bytes = randomBytes } = {}) {
    this.username = username;
    this.masterToken = masterToken;
    this.now = now;
    this.bytes = bytes;
    this.tickets = new Map();
  }

  create(backend) {
    this.#purge();
    if (!['claude', 'codex', 'opencode'].includes(backend)) throw Error('invalid_backend');
    if (this.tickets.size >= maximumTickets) throw Error('too_many_pairings');
    const ticket = this.bytes(32).toString('base64url');
    const expiresAt = this.now() + ticketLifetimeMs;
    this.tickets.set(digest(ticket), { backend, expiresAt });
    return { ticket, expiresAt };
  }

  exchange(ticket, backend) {
    this.#purge();
    if (typeof ticket !== 'string' || ticket.length !== 43 ||
        typeof backend !== 'string') return null;
    const key = digest(ticket);
    const pending = this.tickets.get(key);
    if (!pending || pending.backend !== backend) return null;
    this.tickets.delete(key);
    const deviceId = this.bytes(18).toString('base64url');
    return `p1.${deviceId}.${signature(this.masterToken, deviceId)}`;
  }

  authenticate(header) {
    if (typeof header !== 'string' || !header.startsWith('Basic ')) return false;
    let decoded;
    try { decoded = Buffer.from(header.slice(6), 'base64').toString('utf8'); } catch { return false; }
    const separator = decoded.indexOf(':');
    if (separator < 0 || decoded.slice(0, separator) !== this.username) return false;
    const credential = decoded.slice(separator + 1);
    const suppliedMaster = Buffer.from(digest(credential));
    const expectedMaster = Buffer.from(digest(this.masterToken));
    if (suppliedMaster.length === expectedMaster.length &&
        timingSafeEqual(suppliedMaster, expectedMaster)) return true;
    const match = /^p1\.([A-Za-z0-9_-]{24})\.([A-Za-z0-9_-]{43})$/.exec(credential);
    if (!match) return false;
    const expected = Buffer.from(signature(this.masterToken, match[1]));
    const actual = Buffer.from(match[2]);
    return expected.length === actual.length && timingSafeEqual(expected, actual);
  }

  #purge() {
    const now = this.now();
    for (const [key, value] of this.tickets) {
      if (value.expiresAt <= now) this.tickets.delete(key);
    }
  }
}
