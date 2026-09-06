# DeepSeek-v4-Flash-DSpark-2x-DGX-Spark-SGLang

MIT-licensed recipe for serving [deepseek-ai/DeepSeek-V4-Flash-Vision-Exp](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp) at TP=2 on two NVIDIA DGX Sparks connected via a ConnectX cable, using [SGLang](https://github.com/sgl-project/sglang).

## Layout

```
.
├── README.md                              # this file
├── LICENSE                                # MIT
├── AGENTS.md                              # recipe conventions
├── patches/                               # source-level patches for the image
├── recipe/
│   ├── env/.env.dspark.example            # NCCL + SGLang env knobs (rename to .env)
│   └── scripts/{start,stop}-tp2.sh         # TP=2 launcher + bring-down
├── examples/api-call.sh                   # one-line curl demos
└── tests/smoke-test.sh                    # /v1/models + PONG round-trip
```

## Quickstart

```bash
# Pre-conditions (both sparks):
#   - ConnectX cable bound to 10.0.22.0/24, MTU 9000 on enp1s0f1np1
#   - HF snapshot mirrored on both sparks (rsync head → worker, sudo on both ends)
#   - sudo docker login docker.io -u blivioniag  # one-time, image is private

cp recipe/env/.env.dspark.example recipe/env/.env.dspark
./recipe/scripts/start-tp2.sh worker   # worker first
./recipe/scripts/start-tp2.sh head     # head second
./tests/smoke-test.sh 192.168.1.123 8888
```

## Hardware

- 2× NVIDIA DGX Spark (Grace + GB10, 128 GiB unified memory, Ubuntu 24.04)
- 1× ConnectX cable (MTU 9000)
- 1× 1 TB NVMe per spark (HF cache + workspace)

## Software (per spark)

- Docker 24+ with NVIDIA Container Toolkit
- NCCL 2.21+
- The patched image: `docker.io/blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001` (private — `sudo docker login` required; pulled automatically by `start-tp2.sh`)

## Image

The patched image = `lmsysorg/sglang:dev-v4f-2dgx-v2` + 2 source-level patches (see `patches/`). Mirror-locked to upstream commit `452239a74f5b31798290f57aeac2645d98a52f44`. Rebuild with `patches/build.sh`.

## Patches

| File | Change | Reason |
|---|---|---|
| `python/sglang/srt/models/deepseek_v4.py` | skip `aligner.*` / `dspark_aligner.*` weights in `load_weights` | the published checkpoint doesn't ship training-only alignment heads |
| `python/sglang/srt/utils/offloader.py` | pass `tie_weights=False` to `functional_call` | vision tower's separate tied-weight group conflicts at default |

See `patches/` for the unified diffs, the overlay Dockerfile, and `build.sh`.

## Attribution

| Component | Source | License | Used for |
|---|---|---|---|
| `DeepseekV4ForCausalLM` model class | [sgl-project/sglang PR #37479](https://github.com/sgl-project/sglang/pull/37479) | Apache-2.0 | Model class for the checkpoint |
| `b12x` FlashMLA backend (sm120 / GB10) | [sgl-project/sglang](https://github.com/sgl-project/sglang) | Apache-2.0 | Attention backend that runs on the GB10 |
| `dev-v4f-2dgx-v2` base image | [sgl-project/sglang](https://github.com/sgl-project/sglang) (cookbook DGX Spark cell) | Apache-2.0 | Base image with DGX Spark NCCL/ConnectX/CUDA pins; we layer 2 patches on top |
| NCCL / ConnectX-7 playbook conventions | [NVIDIA/dgx-spark-playbooks](https://github.com/NVIDIA/dgx-spark-playbooks) | Apache-2.0 | `NCCL_IB_DISABLE=0`, `NCCL_IB_HCA=<hca>` etc. |
| 2-node TP=2 architecture (ConnectX subnet, MTU 9000, single HCA) | [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) | MIT | Architectural reference; launcher shape |
| Model checkpoint | [deepseek-ai/DeepSeek-V4-Flash-Vision-Exp](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp) rev `86f746b` | DeepSeek license | The model served |
| Lifecycle scripts (`start-tp2.sh`, `stop-tp2.sh`, `tests/smoke-test.sh`) | This recipe | MIT | Operator-side wrappers |

Pins: upstream SGLang commit `452239a74f5b31798290f57aeac2645d98a52f44`; HF checkpoint revision `86f746b36186f0e567729a5c06a8c918caba82a9`. NCCL / CUDA / kernel follow whatever the DGX Spark ships.

## Known issues

- **Single HCA.** Dual-HCA NCCL fails GID validation; we use `NCCL_IB_HCA=rocep1s0f1` (~half dual-HCA bandwidth).
- **No expert parallelism.** `--ep-size 2 --moe-a2a-backend deepep` hits `AssertionError: expert_location_metadata is not None` at `sglang/srt/eplb/expert_location_dispatch.py:45`. TP=2 only.
- **Preview channel.** `dev-v4f-2dgx-v2` is upstream's preview; new `v*` releases may require patch rebase.

## License

MIT. See `LICENSE`. Upstream attribution is in the Attribution section above.
