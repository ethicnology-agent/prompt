// One owned SDK input stream. Closing drops queued inputs and wakes the reader.
export class InputStream {
  constructor() { this.values = []; this.waiter = null; this.closed = false; }
  [Symbol.asyncIterator]() { return this; }
  next() {
    if (this.values.length) return Promise.resolve({ value: this.values.shift(), done: false });
    if (this.closed) return Promise.resolve({ done: true });
    return new Promise((resolve) => { this.waiter = resolve; });
  }
  push(value) {
    if (this.closed) throw new Error('input_closed');
    if (this.waiter) { const resolve = this.waiter; this.waiter = null; resolve({ value, done: false }); }
    else this.values.push(value);
  }
  return() { this.close(); return Promise.resolve({ done: true }); }
  close() { this.closed = true; this.values.length = 0; this.waiter?.({ done: true }); this.waiter = null; }
}
