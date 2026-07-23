# Pages-only site refresh

## Goal

Update the public website and its social preview without rebuilding MegaWhisper, moving an immutable release tag, or replacing release assets. The first use changes the Telegram/Open Graph image from a full application screenshot to the square MegaWhisper icon and makes the public installation guide English-only.

## Confirmed current state

- GitHub Pages is deployed by Actions as one artifact containing both the static website and the signed Flatpak OSTree repository.
- The live v2.1.1 page uses `img/history.png` as `og:image` and requests a large social card.
- The published v2.1.1 recovery bundle contains the signed site, Flatpak repository, install descriptors, release key, and recovery metadata.
- The active Flatpak commit is `ed00fa4052fdb2860dc7783c56a1f48add4d0615719e33a0d2f6bec778fa7d07`.
- The public `main` branch is protected, so the change must arrive through a pull request.

## Selected design

Add a manually dispatched Pages-only workflow in the public repository. Its input is an exact stable release tag, initially `v2.1.1`.

The workflow will:

1. Check out the exact public `main` commit that contains the website update.
2. Resolve the requested published stable release and immutable asset identities through the GitHub API.
3. Download only the recovery bundle, `SHA256SUMS`, its detached signature, and the release key by immutable asset ID.
4. Verify GitHub sizes and SHA-256 digests, the pinned release-key fingerprint, the checksum signature, and the recovery-bundle checksum.
5. Extract and verify the signed v2.1.1 site and Flatpak states with the existing CI helpers.
6. Build the desired website from tracked `site/` and `img/`, while preserving the signed `.flatpakref` and `.flatpakrepo` files from the verified release state.
7. Generate a deterministic site manifest, run strict site verification, and assemble it with the unchanged verified OSTree repository.
8. If the live state already equals the desired state, finish successfully without deploying. Otherwise require the live state to equal the signed baseline before deploying.
9. Deploy the desired Pages artifact and verify the exact live website files, install descriptors, OSTree metadata, and Flatpak commit.
10. If deployment or post-deployment verification fails, deploy the untouched signed baseline as rollback and verify it.

The workflow uses the existing `megawhisper-public-distribution` concurrency group, the `github-pages` environment, and only `contents: read`, `pages: write`, and `id-token: write` permissions.

## Invariants

- The v2.1.1 tag, release state, asset IDs, asset bytes, and signatures are not changed.
- The application binaries are not rebuilt or uploaded.
- The active Flatpak commit remains unchanged.
- The selected release must still be the exact latest stable release.
- The checked-out source must still be current public `main` immediately before mutation begins.
- The workflow cannot deploy over an unknown live state.
- Re-running the same refresh is idempotent.
- Rollback always uses the original signed v2.1.1 site and Flatpak state.

## Website changes

- Add a 512x512 PNG rendered from the existing MegaWhisper SVG icon.
- Point `og:image` and `twitter:image` to the new absolute HTTPS URL.
- Declare PNG type and exact dimensions.
- Use `twitter:card=summary` instead of `summary_large_image`.
- Translate public `INSTALL.md` to English and update package examples to v2.1.1.

The website remains bilingual. Russian `data-ru` strings are product localization, not repository documentation.

## Verification

- `actionlint` passes for all workflows.
- All shell scripts pass `bash -n` and relevant `shellcheck` checks.
- A staged release site passes `verify-pages-site.sh` in strict mode.
- The social image is a regular 512x512 PNG and all referenced local files exist.
- Public root documentation contains no Cyrillic text.
- The manual refresh completes without application build jobs.
- The live page serves the new OG metadata and PNG over HTTPS.
- The live signed Flatpak commit remains the expected v2.1.1 commit.

## Rollback and recovery

The workflow uploads both desired and signed-baseline Pages artifacts before deployment. A failed desired deployment triggers the signed-baseline deployment and exact verification.

The immutable v2.1.1 recovery bundle continues to contain the previous website. Running the existing release recovery operation will therefore restore the old social preview. The next normal release will include the updated website in its newly signed recovery bundle.

A second, different website refresh backed by the same immutable release intentionally fails closed because the live state would match neither the signed baseline nor the newly requested state.

Telegram caches link previews. After a successful deployment, refresh `https://dxvsi.github.io/MegaWhisper/` through `@WebpageBot` and validate with a newly sent message.

## Out of scope

- Building or changing application packages.
- Creating a new application release.
- Mutating v2.1.1 tags or release assets.
- Changing Flatpak permissions, repository contents, or signing keys.
- Guaranteeing Telegram's final card layout, which remains client-controlled.

## Implementation status

Implemented through [public PR #10](https://github.com/DXVSI/MegaWhisper/pull/10):

- Added the Pages-only workflow and deterministic staging helpers.
- Added immutable release asset, checksum, signature, recovery, site, and Flatpak verification.
- Added latest-release and protected-main freshness checks.
- Added idempotent desired-state detection and signed-baseline rollback.
- Added the social PNG and exact metadata validation.
- Translated the public installation guide to English.

Local end-to-end verification against the real published v2.1.1 recovery bundle succeeded. The reconstructed signed baseline matched the previous live Pages state, including the signed Flatpak static delta and commit `ed00fa4052fdb2860dc7783c56a1f48add4d0615719e33a0d2f6bec778fa7d07`.

[Pages refresh run 29816200635](https://github.com/DXVSI/MegaWhisper/actions/runs/29816200635) completed successfully in 57 seconds without application build jobs or rollback. Independent live verification confirmed HTTP 200 for the page and 512x512 PNG, exact deployed icon bytes and social metadata, version 2.1.1, and the unchanged Flatpak commit.

## Product-first hero redesign, 2026-07-24

### Goal

Replace the first-screen composition with a clearer presentation of the real
application. The visitor should understand the product, supported execution
paths, and primary installation action without decoding decorative overlays.

### Confirmed current state

- The hero wraps `img/main.png`, which already contains native window chrome,
  in a second artificial title bar.
- The product image is darkened with `brightness(0.82)`, desaturated, enlarged,
  cropped, rotated, and partly covered by a decorative waveform panel.
- Two floating notes overlap the product frame and consume vertical space
  without explaining the model/runtime choices introduced for 2.2.0.
- At a 1500x850 viewport the real interface occupies a small, low-contrast
  fraction of the first screen.
- The page already contains verified Qt Quick screenshots. No new external
  visual dependency or generated mockup is required.

### Alternatives

1. Keep the current composition and only increase image brightness. This does
   not remove the duplicated window frame, visual noise, or weak hierarchy.
2. Add an interactive screenshot carousel. This increases JavaScript,
   accessibility, and input-state surface before the visitor understands the
   primary product.
3. Use a large direct product frame with concise capability facts. This keeps
   the page truthful, static, fast, and visually focused.

Option 3 is selected.

### Selected design

- Keep the existing industrial dark palette and bilingual contract.
- Replace the nested mock window, waveform, stage index, and floating notes
  with one large, unfiltered screenshot in a restrained product frame.
- Tighten the headline and lead around Linux dictation and user-controlled
  processing.
- Keep Flatpak and latest-release actions above the fold.
- Replace numbered generic facts with three explicit capability cards:
  local Whisper and Parakeet, CPU with Vulkan acceleration, and
  OpenAI-compatible cloud transcription.
- Preserve the existing screenshot file, release links, privacy wording,
  Content Security Policy, no-tracking policy, and no-external-runtime rule.
- Collapse to a single-column composition before the product frame becomes too
  narrow, and keep all actions usable at 320 CSS pixels.

### Acceptance and verification

- The real application screenshot is not filtered, rotated, cropped, or
  covered.
- The hero contains no duplicate window title bar.
- English and Russian strings remain complete.
- Keyboard focus, reduced motion, forced colors, and mobile navigation remain
  valid.
- The page renders without horizontal overflow at 1500x850, 1024x768,
  768x1024, and 390x844 viewports.
- `verify-pages-site.sh` passes in strict release mode on a fully staged site.
- HTML, JavaScript, XML, local asset inventory, site size, and release links
  pass the existing fail-closed checks.

### Risks and rollback

The change is limited to tracked HTML/CSS and this document. Rollback is the
previous public `main` commit or the existing signed Pages recovery path. No
application package, release tag, Flatpak repository, signing key, permission,
or release asset changes.

### Out of scope

- Changing the application screenshots.
- Adding animation, a carousel, analytics, external fonts, or remote scripts.
- Changing package installation or release publication logic.
- Redesigning lower page sections in the same change.

### Implementation status

Approved by the user for immediate implementation after documentation.
Implemented on `redesign/product-first-hero`:

- Removed the duplicate title bar, rotated mock window, screenshot filter,
  crop, waveform footer, stage index, and overlapping notes.
- Added the direct full 1400x900 Qt Quick screenshot, restrained product
  frame, concise bilingual copy, and three exact capability cards.
- Inspected headless Chrome renders at 1500x853, 1024x768, 768x1024, and
  390x844; the exact overflow contract also passed at the 320-pixel minimum
  and on both sides of the 940/941-pixel layout breakpoint.
- DevTools measurements confirmed exact viewport and scroll widths in English
  and Russian at all four sizes, with the 1400-pixel source image loaded.
- Strict release-site verification passed with all current screenshots,
  release links, CSP, local assets, XML, JavaScript, and a 979199-byte payload.
- `git diff --check` passed.
