import { test } from "node:test";
import assert from "node:assert/strict";
import { encodePairCode, decodePairInput, parsePairHash } from "../src/lib/paircode.js";

const TOKEN = "Ab3-_xYz01234567890x";
const BASE = "https://nidus-relay.example.workers.dev";

test("round-trips a pairing code", () => {
  const got = decodePairInput(encodePairCode(TOKEN, BASE));
  assert.deepEqual(got, { token: TOKEN, base: BASE });
});

test("tolerates whitespace and line breaks from a clipboard", () => {
  const code = encodePairCode(TOKEN, BASE);
  const messy = `  ${code.slice(0, 10)}\n${code.slice(10)}  `;
  assert.deepEqual(decodePairInput(messy), { token: TOKEN, base: BASE });
});

test("accepts a pasted pairing LINK too (what people actually keep)", () => {
  const link = `https://paramostudio.github.io/Nidus/#pair=${TOKEN}~${encodeURIComponent(BASE)}`;
  assert.deepEqual(decodePairInput(link), { token: TOKEN, base: BASE });
});

test("parses the QR hash", () => {
  const hash = `#pair=${TOKEN}~${encodeURIComponent(BASE)}`;
  assert.deepEqual(parsePairHash(hash), { token: TOKEN, base: BASE });
});

test("round-trips a base with non-ASCII (UTF-8 safety)", () => {
  const weird = "https://relé-ñ.example.dev";
  assert.deepEqual(decodePairInput(encodePairCode(TOKEN, weird)), { token: TOKEN, base: weird });
});

test("rejects junk instead of silently half-pairing", () => {
  assert.equal(decodePairInput(""), null);
  assert.equal(decodePairInput("hello"), null);
  assert.equal(decodePairInput("NI-!!!not base64!!!"), null);
  assert.equal(parsePairHash("#nope=1"), null);
});

test("matches what Swift produces (base64url of `token~base`, no padding)", () => {
  // Swift: base64url(Data("\(token)~\(relayBase)".utf8)) with +→- /→_ and = stripped.
  const code = encodePairCode(TOKEN, BASE);
  assert.ok(code.startsWith("NI-"));
  assert.ok(!code.includes("="), "no padding");
  assert.ok(!/[+/]/.test(code), "url-safe alphabet only");
});
