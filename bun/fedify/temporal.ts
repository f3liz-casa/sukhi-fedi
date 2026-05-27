// Bun 1.3 にネイティブ Temporal がまだ無いので polyfill を globalThis に
// 据え置く。Fedify 2 の vocab は `esnext.temporal` lib 由来の組み込み
// Temporal 型を期待しているため、handler 側は `import { Temporal } from
// "@js-temporal/polyfill"` を避けてグローバルを参照する。このファイルを
// import するだけで polyfill が install される。
import { Temporal as Polyfill } from "@js-temporal/polyfill";

const g = globalThis as { Temporal?: unknown };
if (g.Temporal === undefined) g.Temporal = Polyfill;

export const nowInstant = (): Temporal.Instant => Temporal.Now.instant();
