// Minimal standards-based ZIP STORE writer. No compression, remote libraries or executable content.
const encoder = new TextEncoder();
const table = Uint32Array.from({ length: 256 }, (_, n) => { for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1; return n >>> 0; });
function crc32(bytes) { let c = 0xffffffff; for (const b of bytes) c = table[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
function header(size) { const bytes = new Uint8Array(size); const view = new DataView(bytes.buffer); return { bytes, u16: (o, v) => view.setUint16(o, v, true), u32: (o, v) => view.setUint32(o, v, true) }; }
function concat(parts) { const out = new Uint8Array(parts.reduce((n, x) => n + x.length, 0)); let i = 0; for (const p of parts) { out.set(p, i); i += p.length; } return out; }
export function zipStore(files) {
  const locals = [], central = []; let offset = 0;
  for (const [path, content] of Object.entries(files)) {
    const name = encoder.encode(path), data = encoder.encode(content), crc = crc32(data);
    const h = header(30); h.u32(0, 0x04034b50); h.u16(4, 20); h.u16(6, 0x800); h.u16(12, 33);
    h.u32(14, crc); h.u32(18, data.length); h.u32(22, data.length); h.u16(26, name.length);
    locals.push(h.bytes, name, data);
    const c = header(46); c.u32(0, 0x02014b50); c.u16(4, 20); c.u16(6, 20); c.u16(8, 0x800); c.u16(14, 33);
    c.u32(16, crc); c.u32(20, data.length); c.u32(24, data.length); c.u16(28, name.length); c.u32(42, offset);
    central.push(c.bytes, name); offset += h.bytes.length + name.length + data.length;
  }
  const dir = concat(central), end = header(22), count = Object.keys(files).length;
  end.u32(0, 0x06054b50); end.u16(8, count); end.u16(10, count); end.u32(12, dir.length); end.u32(16, offset);
  return concat([...locals, dir, end.bytes]);
}
