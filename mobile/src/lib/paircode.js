/**
 * The pairing codec — pure, and unit-tested on purpose.
 *
 * A pairing is `{token, base}`. It normally arrives by QR (a URL with `#pair=token~encodedBase`), but it
 * MUST also be carriable by hand: on iOS a home-screen web app gets its own storage container, so a
 * pairing made in Safari is invisible to the installed app, which starts up unpaired and mute.
 *
 * The hand-carried form is `NI-<base64url(token~base)>` — one opaque blob that survives a clipboard
 * round trip and doesn't look like a tappable link. A silent mangling here strands someone with a code
 * that looks right and does nothing, which is why this file has tests.
 */

const PREFIX = "NI-";

function b64urlEncode(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(code) {
  const padded = code.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((code.length + 3) % 4);
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

export function encodePairCode(token, base) {
  return PREFIX + b64urlEncode(`${token}~${base}`);
}

/** Parses a `#pair=token~encodedBase` fragment (from the QR). */
export function parsePairHash(hash) {
  const m = /[#&]pair=([^&]+)/.exec(hash || "");
  if (!m) return null;
  const [token, encodedBase] = decodeURIComponent(m[1]).split("~");
  if (!token) return null;
  return { token, base: decodeURIComponent(encodedBase || "") };
}

/**
 * Accepts what people actually paste: the code itself, or a whole pairing link. Whitespace-tolerant.
 * Returns `{token, base}` or null.
 */
export function decodePairInput(input) {
  const text = (input || "").trim();
  if (!text) return null;

  if (text.includes("#pair=")) return parsePairHash(text.slice(text.indexOf("#")));

  const code = text.replace(/\s+/g, "");
  if (!code.startsWith(PREFIX)) return null;
  try {
    const [token, base] = b64urlDecode(code.slice(PREFIX.length)).split("~");
    if (!token) return null;
    return { token, base: base || "" };
  } catch {
    return null;
  }
}
