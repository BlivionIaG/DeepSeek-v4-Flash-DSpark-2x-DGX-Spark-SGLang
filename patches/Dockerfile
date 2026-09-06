# Apply on top of the upstream `lmsysorg/sglang:dev-v4f-2dgx-v2` image
# (built by sgl-project/sglang GitHub Actions from commit
# 452239a74f5b31798290f57aeac2645d98a52f44).
#
# Build context layout expected by build.sh:
#   patches/
#     Dockerfile            (this file)
#     deepseek_v4.py.patch
#     offloader.py.patch
#
# build.sh does:
#   1. clone sgl-project/sglang at the pinned commit
#   2. apply both patches (must apply cleanly — fail otherwise)
#   3. `docker build` from a generated Dockerfile that does
#      `FROM lmsysorg/sglang:dev-v4f-2dgx-v2-patched` + COPY both files
#   4. `docker save` to a tarball for offline `docker load`

FROM lmsysorg/sglang:dev-v4f-2dgx-v2-patched
COPY deepseek_v4.py /sgl-workspace/sglang/python/sglang/srt/models/deepseek_v4.py
COPY offloader.py   /sgl-workspace/sglang/python/sglang/srt/utils/offloader.py
