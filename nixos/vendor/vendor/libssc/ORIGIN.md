# libssc source origin

This directory vendors the upstream libssc build sources used by the Xiaomi
sheng sensor stack. Non-build documentation and debugging captures are omitted.

- Upstream: https://codeberg.org/DylanVanAssche/libssc
- Tag: `v0.3.0`
- Tag object: `c161afe5739a2396953042d1ea3219320e5967a2`
- Source commit: `256552587dfb0653a7cddec6145826533d42b26e`

The source is vendored because Codeberg rejects source fetches from GitHub
Actions runners with HTTP 403. Device-specific changes remain as downstream
patches outside this directory.
