# Fonts (subset, self-hosted)

These WOFF2 files are **subsets** of OFL-licensed fonts, containing only the
glyphs used by the legal pages (terms / privacy). They are embedded as base64
into the served HTML at compile time (see `SukhiFedi.Web.LegalController`) so
the pages make **no external font request** — a Google Fonts `<link>` would
leak the reader's IP, which is the wrong thing to do on a privacy page.

- `bizudpgothic.woff2` — BIZ UDPGothic (Japanese pages). © Morisawa Inc.
- `nanumgothic.woff2`  — Nanum Gothic (Korean pages). © NAVER Corp.

Both under the SIL Open Font License 1.1 — see `*-OFL.txt`. Source TTFs:
github.com/google/fonts (ofl/bizudpgothic, ofl/nanumgothic). Re-subset with
`pyftsubset <ttf> --text-file=<chars> --flavor=woff2`.
