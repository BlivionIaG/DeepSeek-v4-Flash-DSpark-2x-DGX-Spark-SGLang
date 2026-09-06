# patches/ — SGLang source-level patches for DeepSeek-V4-Flash-Vision-Exp on DGX Spark

Two surgical patches applied on top of the upstream SGLang image
`lmsysorg/sglang:dev-v4f-2dgx-v2` (built by sgl-project/sglang Actions
from commit `452239a74f5b31798290f57aeac2645d98a52f44`):

| Patch | File | Lines | Why |
|---|---|---|---|
| `deepseek_v4.py.patch` | `python/sglang/srt/models/deepseek_v4.py` | +2 | Skip `aligner.*` / `dspark_aligner.*` weights in `load_weights`. The published `DeepSeek-V4-Flash-Vision-Exp` safetensors don't ship training-only alignment/distillation heads; without the skip, weight load crashes on `KeyError`. |
| `offloader.py.patch` | `python/sglang/srt/utils/offloader.py` | +1 keyword arg | Pass `tie_weights=False` to `functional_call`. The vision tower has its own tied-weight group independent from the LLM tower's; default `tie_weights=True` causes a tied-weight consistency crash when CPU offloading is active. |

The patches **must apply cleanly against the upstream image at the
pinned commit**. If `patch` reports fuzz or rejects, the upstream
SGLang source has drifted from the pinned commit — rebase the
patches before rebuilding.

## What's here

```
patches/
├── Dockerfile             # the 3-line overlay that produces the patched image
├── README.md              # this file
├── build.sh               # rebuild the patched image from a clean SGLang checkout
├── deepseek_v4.py.patch   # unified diff for python/sglang/srt/models/deepseek_v4.py
└── offloader.py.patch     # unified diff for python/sglang/srt/utils/offloader.py
```

## How to apply the patches manually

From a clean SGLang checkout at commit `452239a74f5b31798290f57aeac2645d98a52f44`:

```bash
cd sglang                # the SGLang repo root
patch -p1 < /path/to/patches/deepseek_v4.py.patch
patch -p1 < /path/to/patches/offloader.py.patch
```

Both should report "patching file `python/sglang/srt/...`" with no fuzz
and no rejects.

## How to rebuild the image

```bash
cd /path/to/patches
./build.sh
```

`build.sh` will:
1. Clone sgl-project/sglang at the pinned commit into a temp dir
2. Apply both patches (fail if either doesn't apply cleanly)
3. Build a new image tagged `docker.io/<your-dockerhub-user>/sglang:dev-v4f-2dgx-v2-patched-v3_patch002`
   (or whatever tag you pass as `$1`)
4. `docker save` to a tarball for offline distribution

Default image name matches the recipe's `SGLANG_IMAGE` default in
`recipe/env/.env.dspark.example`.

## When to rebase

The patches are mirror-locked to commit `452239a74f5b31798290f57aeac2645d98a52f44`.
When SGLang ships a new `dev-v4f-2dgx-v*` preview:

1. Check out the new commit in a clean SGLang working tree
2. Try `patch -p1 < each.patch`
3. If either patch fails:
   - Inspect the upstream change at the same line range
   - Port the patch forward by hand (the underlying intent is
     stable — skip aligner weights; disable tied-weight check in
     the offloader's forward call)
   - Bump the patch version (e.g. `_patch002` for the new build)
4. Re-run `./build.sh` + push the new tag

## See also

- `recipe/env/.env.dspark.example` — `SGLANG_IMAGE` default points at
  the published image built from these patches
- `../README.md` Attribution section — provenance for the upstream
  SGLang components these patches layer on top of
