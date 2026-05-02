# CATHA Connect Cloud recursive dependency fix

The previous manifest listed only the top-level R packages. Posit Connect Cloud installed those direct packages but did not have the transitive dependencies available when compiling them, e.g. `signal` for `tuneR`, `cli`/`rlang`/`tibble` for `dplyr`, and `htmltools`/`htmlwidgets` for `DT`.

This bundle fixes that by:

1. removing the unused `soundgen` dependency from the app;
2. providing a manifest with recursive R dependencies; and
3. keeping Python/Basic Pitch disabled for Connect Cloud deployment.

## Files to copy

Copy these files to the root of your GitHub repository:

- `manifest.json`
- `.rscignore`
- `generate_connect_manifest_R_recursive.R`

Also replace your local app files with:

- `app.R`
- `install_packages.R`

## Recommended regeneration step

The most robust workflow is to regenerate the manifest locally from your actual app folder:

```r
setwd("/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v9")
source("generate_connect_manifest_R_recursive.R")
```

Then commit the resulting `manifest.json`.

## Python / Basic Pitch

Python is intentionally ignored here. On Connect Cloud, the Basic Pitch buttons may remain visible, but they will only work if a compatible Python/Basic Pitch environment exists on the server. For Connect Cloud, use the core R-only CATHA features. For hosted Basic Pitch support, use a Docker-capable host.
