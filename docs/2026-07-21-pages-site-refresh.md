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

Implemented locally on `fix/site-preview-icon` without committing, pushing, or changing external state:

- Added the Pages-only workflow and deterministic staging helpers.
- Added immutable release asset, checksum, signature, recovery, site, and Flatpak verification.
- Added latest-release and protected-main freshness checks.
- Added idempotent desired-state detection and signed-baseline rollback.
- Added the social PNG and exact metadata validation.
- Translated the public installation guide to English.

Local end-to-end verification against the real published v2.1.1 recovery bundle succeeded. The reconstructed signed baseline matches the current live Pages state, including the signed Flatpak static delta and commit `ed00fa4052fdb2860dc7783c56a1f48add4d0615719e33a0d2f6bec778fa7d07`. The staged result correctly selected `mode=deploy`. External deployment remains pending until the changes are reviewed, committed, merged through the protected public branch, and manually dispatched.
