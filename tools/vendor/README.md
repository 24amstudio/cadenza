# Vendored development tooling

`anti-slop/` contains the generic Oxlint plugin from [dmmulroy/anti-slop](https://github.com/dmmulroy/anti-slop), commit `13909c9e07590f5a85d93c62712259fe14a883f7`. Its MIT license and upstream version marker are preserved in that directory. Source was reused from an existing local installation; no plugin package was downloaded.

The generic entry point, its rules, shared helpers, and required internal vendored code are included. The separate Effect plugin is omitted because Cadenza does not depend on Effect. This code runs only in development checks and must not be bundled into Cadenza Host or Cadenza Remote. Upstream files are excluded from Cadenza's own lint, formatting, and line-limit passes.
