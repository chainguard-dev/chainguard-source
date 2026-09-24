# chainguard-source
Fetch the open source code related to Chainguard packages and images, as defined in the SBOMs.

Chainguard images contain two types of APKs:

- **Public Wolfi packages** (`pkg:apk/wolfi/*`) — open source packages built from the [Wolfi](https://github.com/wolfi-dev) repository
- **Enterprise packages** (`pkg:apk/chainguard/*`) — private packages served from `apk.cgr.dev`

`chainguard-source` downloads source for both. When using `--image`, the script reads `/etc/apk/repositories` from the image to determine where each APK is served from, tries each repository in order, and falls back to `apk.cgr.dev` with authentication for packages not found in any public repo.

Additional dependencies for enterprise images:

- [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) — reads the APK repository list from the image
- [`chainctl`](https://edu.chainguard.dev/chainguard/chainctl/) — generates a pull token for authenticating against `apk.cgr.dev`
- [`yq`](https://github.com/mikefarah/yq) — optional; needed to enumerate the patches a build applied

# Usage

When using `--image` with a `cgr.dev/ORG/image` URL, the Chainguard org is auto-detected:
```
$ chainguard-source -y --image cgr.dev/example.com/redis:latest
$ chainguard-source --yes --image cgr.dev/chainguard/wolfi-base:latest
```

For `--package` or `--sbom` mode, specify the org explicitly with `--org`:
```
$ chainguard-source -y --org example.com --sbom /tmp/image.sbom.spdx.json
$ chainguard-source --yes --package hello-wolfi
$ chainguard-source -y -p hello-wolfi-2.12.1-r6
```

Fetch sources from a local SBOM file:
```
$ chainguard-source -y --sbom /tmp/midnight-commander.sbom.spdx.json
$ chainguard-source -y -s /tmp/wordpress.latest.sbom.spdx.json
```

Authentication uses `chainctl` — ensure you are logged in before running:
```
$ chainctl auth login
```

# Patches

Upstream source alone does not tell you what Chainguard changed. Every
Chainguard APK embeds the locked melange build configuration that produced it,
as `.melange.yaml` in the APK control section, and that configuration names
every patch applied during the build.

`chainguard-source` extracts that configuration and then tries to retrieve the
patch files themselves, in this order:

1. **From a `.patches/` directory in the APK control section.** This requires
   no source repository access at all — anyone entitled to pull the APK can
   read the patches applied to it. This is the path that works for enterprise
   packages. melange does not ship patches here yet; when it does, this lights
   up with no further changes to this tool.
2. **From the melange build configuration repository** referenced by the SBOM,
   checked out at the exact build commit. Patches live in a directory named
   after the configuration, right next to it.
3. **From the public `wolfi-dev/os` mirror**, if the repository named by the
   SBOM cannot be read. Public Wolfi packages are built out of a private
   monorepo and their SBOMs point at it, so even a wholly open source package's
   provenance reference is unresolvable from outside Chainguard. The same
   configurations and patches are mirrored publicly, so they are still
   retrievable — but the exact build commit does not exist in the mirror, so
   anything obtained this way is reported as `MIRROR` rather than `OK`. Pass
   `--no-mirror` to disable this and accept only exact-commit provenance.

To collect build configurations and patches without downloading gigabytes of
upstream source, use `--patches-only`:

```
$ chainguard-source -y --patches-only --package busybox
$ chainguard-source -y --patches-only --package python-3.13
$ chainguard-source -y --patches-only --org example.com --image cgr.dev/example.com/someimage:latest
```

Results land under `sources/<target>/patches/<package>/`, with a reconciliation
of what was applied against what was actually retrieved in
`sources/<target>/patches/MANIFEST.txt`:

```
STATUS     PACKAGE                                  PATCH
OK         busybox                                  CVE-2025-46394.patch
MIRROR     python-3.13                              gh-127301.patch
MISSING    some-enterprise-package                  some-fix.patch
```

- `OK` — retrieved from the exact source the build used.
- `MIRROR` — retrieved from the public mirror, which carries the same patch but
  cannot be pinned to the build commit named in the SBOM.
- `MISSING` — the build applied that patch to software you received, but its
  contents could not be retrieved at all. Today that is every patch belonging
  to an enterprise package, for any caller without access to the private build
  configuration repository.

# Tests

`test/test-patches.sh` exercises the patch collection logic offline, against a
synthetic APK fixture. No network access required:

```
$ ./test/test-patches.sh
```
