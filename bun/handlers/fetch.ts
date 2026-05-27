// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Signed AP document fetch. Mastodon Secure Mode と Misskey/Sharkey の
// "Authorized fetch" 系は GET にも HTTP Signature を要求してくる。
// fedify の `getAuthenticatedDocumentLoader` が signed GET を出して
// くれる。
//
// `signAs` が無い時(local actor が一つも居ない fresh instance)は
// 署名なしの GET ─ 以前と同じリーチ。
//
// **double-knocking について**: fedify は `specDeterminer` を渡さない
// と最初に RFC 9421 で投げる(authdocloader.ts L24 / http.ts L721)。
// 失敗したら draft-cavage に切り替えて再送、というのは内蔵されている
// が、いまの fediverse の現実は cavage-12 が圧倒的多数。先に cavage
// で投げて、駄目なら 9421 にする方が一往復で済むことが多い。
// 加えて成功した spec を origin ごとに覚えておけば次回はその一往復
// だけで足りる。
//
// 失敗時はステータスとヘッダを残せるところまで残してログに出す。
// "HTTP 403" の一行だけだと、署名済みかどうか / どっちの spec で
// 落ちたかが見えないので。

import {
  getAuthenticatedDocumentLoader,
  importJwk,
  type HttpMessageSignaturesSpec,
  type HttpMessageSignaturesSpecDeterminer,
} from "@fedify/fedify";
import { cachedDocumentLoader } from "../fedify/context.ts";

export interface FetchPayload {
  uri: string;
  signAs?: {
    keyId: string;
    privateJwk: Record<string, unknown>;
    publicJwk?: Record<string, unknown>;
  };
}

export interface FetchResult {
  document: unknown;
}

// origin ("https://example.tld") → 直近に通った署名仕様。worker プロセス
// ごとに in-memory。永続化はしていない(再起動で失えても害は少ない、
// 次の fetch でまた覚え直す)。
const specMemory = new Map<string, HttpMessageSignaturesSpec>();

const determiner: HttpMessageSignaturesSpecDeterminer = {
  determineSpec(origin: string): HttpMessageSignaturesSpec {
    // 覚えていればそれ、無ければ最大互換の cavage-12 から。
    return specMemory.get(origin) ?? "draft-cavage-http-signatures-12";
  },
  rememberSpec(origin: string, spec: HttpMessageSignaturesSpec): void {
    specMemory.set(origin, spec);
  },
};

export async function handleFetch(payload: FetchPayload): Promise<FetchResult> {
  const signedHint = payload.signAs ? "signed" : "unsigned";

  try {
    let loader: typeof cachedDocumentLoader = cachedDocumentLoader;

    if (payload.signAs) {
      const privateKey = await importJwk(
        payload.signAs.privateJwk as Parameters<typeof importJwk>[0],
        "private",
      );
      loader = getAuthenticatedDocumentLoader(
        {
          keyId: new URL(payload.signAs.keyId),
          privateKey,
        },
        { specDeterminer: determiner },
      ) as typeof cachedDocumentLoader;
    }

    const result = await loader(payload.uri);
    return { document: result.document };
  } catch (err) {
    // fedify は FetchError で status / response 情報を投げてくる。
    // gateway 側から見える NATS error 文字列に少なくとも spec の
    // ヒントは残す。詳細は bun の stdout に出す。
    const origin = safeOrigin(payload.uri);
    const triedSpec = origin ? specMemory.get(origin) ?? "draft-cavage-http-signatures-12" : "?";
    const detail = err instanceof Error ? err.message : String(err);

    console.error(
      JSON.stringify({
        event: "fetch.failed",
        uri: payload.uri,
        signed: signedHint,
        first_tried_spec: triedSpec,
        error: detail,
      }),
    );
    throw new Error(`fetch ${payload.uri} (${signedHint}, first=${triedSpec}) failed: ${detail}`);
  }
}

function safeOrigin(uri: string): string | null {
  try {
    return new URL(uri).origin;
  } catch {
    return null;
  }
}
