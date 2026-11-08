# Vendored libraries (offline, no CDN at runtime)

| File | Library | Version | Source | SHA-256 |
|---|---|---|---|---|
| `three.min.js` | three.js (UMD build, global `THREE`) | r160 (0.160.0) | https://cdnjs.cloudflare.com/ajax/libs/three.js/0.160.0/three.min.js | `170c6789f43217c96b3170f4b42fafe135de7f7cd48497a4218f9757ee1d49fa` |

Downloaded once with curl on 2026-11-08. r160 is the last release that still ships the UMD build; it prints
a deprecation warning in the console, which is expected. HOLO uses no three.js addons: camera controls,
glow, glyph and flow shaders are written in `holo.html`.

Check: `sha256sum chorus/vendor/three.min.js`.
