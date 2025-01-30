# chainguard-image-sources
Download an SBOM and fetch all image sources associated with a Chainguard iamge.

# Dependencies

 - `bash`
 - `cosign`
 - `git`
 - `jq`
 - `sha512sum`

# Example usage


```
$ ./chainguard-image-sources wolfi-base:latest
$ ./chainguard-image-sources python:latest
$ ./chainguard-image-sources jdk
```
