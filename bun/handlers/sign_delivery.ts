// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sign an outbound ActivityPub POST (delivery / inbox post) and hand
// the signed headers back to Elixir. The actual HTTP POST is done by
// `SukhiDelivery.Delivery.Worker` with these headers.
//
// fedify が要求するもの:
//   - signRequest(request, privateKey, keyId, options?)
//   - options.spec = "draft-cavage-http-signatures-12" | "rfc9421"
//   - options.body = ArrayBuffer | null
//       POST body のクローンを fedify 内部でやらせると Bun で潰れる
//       ことがあった(Request.clone は仕様上 OK だが、digest 計算の
//       fast path が失敗する) ─ 明示的に渡す方が安全。
//
// fediverse の実勢:
//   - Mastodon / Misskey / Sharkey / Akkoma / Pleroma 全部 cavage-12
//   - hackers.pub のような Fedify 1.x 製も両方受けるが、cavage の方が
//     verifyRequest の fast path に乗りやすい
//   ─ 既定は cavage-12。

import { signRequest, type HttpMessageSignaturesSpec } from "@fedify/fedify";
import { getImportedPrivateKey, type JwkInput } from "../fedify/key_cache.ts";

export interface SignDeliveryPayload {
  actorUri: string;
  inbox: string;
  body: string;
  privateKeyJwk: JwkInput;
  keyId: string;
  /**
   * Preferred HTTP Signature spec.
   * - "rfc9421"  → Signature-Input + Signature headers (RFC 9421)
   * - "cavage"   → single Signature header (draft-cavage, default)
   */
  algorithm?: "rfc9421" | "cavage";
}

export interface SignDeliveryResult {
  headers: Record<string, string>;
}

const enc = new TextEncoder();

export async function handleSignDelivery(
  payload: SignDeliveryPayload,
): Promise<SignDeliveryResult> {
  const privateKey = await getImportedPrivateKey(payload.privateKeyJwk);
  const bodyBuf = enc.encode(payload.body).buffer as ArrayBuffer;

  const request = new Request(payload.inbox, {
    method: "POST",
    headers: {
      "Content-Type": "application/activity+json",
      "User-Agent": "sukhi-fedi/0.1.0 (+https://sukhi.f3liz.casa/)",
      Accept: "application/activity+json",
    },
    body: payload.body,
  });

  // fedify は `options.spec` を見て cavage / 9421 を切り替える。
  // 引数名を間違えると静かに default (cavage-12) になるので注意。
  const spec: HttpMessageSignaturesSpec =
    payload.algorithm === "rfc9421"
      ? "rfc9421"
      : "draft-cavage-http-signatures-12";

  try {
    const signed = await signRequest(
      request,
      privateKey,
      new URL(payload.keyId),
      { spec, body: bodyBuf },
    );

    const outHeaders: Record<string, string> = {};
    signed.headers.forEach((v, k) => {
      outHeaders[k] = v;
    });

    // 401 を食い続けたとき、実際に署名された header set を覗きたい。
    // 1〜2 deploy 分の追加情報のためのコンソール出力。落ち着いたら剥がす。
    // [[fedify-401-diagnostic]]
    console.error(
      JSON.stringify({
        event: "sign.done",
        inbox: payload.inbox,
        spec,
        body_bytes: bodyBuf.byteLength,
        key_id: payload.keyId,
        out_headers: Object.fromEntries(
          Object.entries(outHeaders).map(([k, v]) => [
            k,
            // Signature は長いので頭尾だけ。
            k.toLowerCase() === "signature" && v.length > 80
              ? v.slice(0, 60) + "...(" + v.length + " chars)"
              : v,
          ]),
        ),
      }),
    );

    return { headers: outHeaders };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    console.error(
      JSON.stringify({
        event: "sign.failed",
        inbox: payload.inbox,
        spec,
        error: detail,
      }),
    );
    throw new Error(`sign for ${payload.inbox} (spec=${spec}) failed: ${detail}`);
  }
}
