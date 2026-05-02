# Connect Cloud cached-version manifest fix

Connect Cloud is failing while installing source packages in a dependency order that causes packages such as `sass`, `vctrs`, and `fontawesome` to be built before their dependencies are available.

This script creates a project-local temporary R library, installs older conservative package versions that are more likely to be available in Connect Cloud's package cache, and generates `manifest.json` from that library using `rsconnect::writeManifest()`.

Run from the CATHA project root:

```r
source("generate_connect_manifest_cached_versions.R")
```

Then commit:

```bash
git add manifest.json .rscignore generate_connect_manifest_cached_versions.R
git rm --cached requirements.txt 2>/dev/null || true
git commit -m "Use Connect Cloud cached R package versions"
git push
```
