# chainguard-source
Fetch the open source code related to Chainguard packages and images, as defined in the SBOMs.

# Example usage

Fetch sources by image name and tag:
```
$ chainguard-source --yes --image cgr.dev/chainguard/wolfi-base:latest
$ chainguard-source -y -i cgr.dev/chainguard/python:latest
$ chainguard-source -y -i cgr.dev/chainguard/jdk
```

Fetch sources by package name and version:
```
$ chainguard-source --yes --package hello-wolfi
$ chainguard-source -y -p hello-wolfi-2.12.1-r6
```

Fetch sources from local SBOM file:
```
chainguard-source -y --sbom /tmp/midnight-commander.sbom.spdx.json
chainguard-source -y -s /tmp/wordpress.latest.sbom.spdx.json
```
