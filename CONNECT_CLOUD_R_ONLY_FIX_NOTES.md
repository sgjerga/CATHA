# CATHA Connect Cloud R-only manifest fix

This bundle fixes the Connect Cloud failure caused by wildcard package versions such as `Version: "*"` in `manifest.json`.

## What changed

- Removed the Python section from `manifest.json`.
- Removed Python environment management from the manifest.
- Pinned direct R package versions instead of using `*`.
- Added `.rscignore` entries for `.venv-basic-pitch`, `requirements.txt`, and Basic Pitch test outputs.

## Files to copy into the CATHA repository root

- `manifest.json`
- `.rscignore`
- `generate_connect_manifest_R_only.R` optional, but recommended

## Recommended local regeneration

The safest approach is to regenerate the manifest on your own machine after installing the R packages:

```r
setwd("/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v9")
source("generate_connect_manifest_R_only.R")
```

Then commit and push:

```bash
git add manifest.json .rscignore generate_connect_manifest_R_only.R
git commit -m "Fix Connect Cloud R-only manifest"
git push
```

## Python / Basic Pitch

This deployment intentionally ignores Python dependencies. Basic Pitch/MIDI notation can remain in the UI as an optional local feature, but it will not run on Connect Cloud unless the host has a configured Python environment and executable paths.
