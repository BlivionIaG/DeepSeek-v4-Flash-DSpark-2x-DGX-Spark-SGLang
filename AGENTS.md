# AGENTS.md — recipe-specific conventions

## Scope

This is the standalone MIT-licensed recipe for running SGLang TP=2
on a 2× DGX Spark topology. It is upstream-shared; for an
operator-side integration that consumes this recipe (ansible role
+ launcher scripts + litellm provider config + recipe-specific
deploy wiring), see the maintainer's `talos-infra` repository.

The two repos serve different audiences:

- **This repo (this file)**: operators who want to deploy SGLang
  TP=2 on their own 2× DGX Spark pair, regardless of what other
  infra they have.
- **talos-infra**: the operator-side integration that consumes
  this recipe and binds it to a specific cluster + litellm
  deployment.

The flag set is identical between the two; the differences are
only the deployment plumbing.

## Conventions

- **Bash** is the canonical script language; all scripts use
  `set -euo pipefail` and source common helpers in
  `recipe/scripts/_lib.sh` (when present). Future scripts should
  match.
- **No proprietary content in this repo.** Don't commit anything
  that isn't Apache-2.0 / MIT / BSD / similar upstream-shareable.
- **Attribution first.** Any new dependency on an upstream work
  (recipe, library, model, kernel flag) gets a row in the
  `Attribution` table in `README.md` in the same commit that adds
  the dependency.
- **Comments that explain WHY, not WHAT.** Code should be
  self-documenting. If a comment is needed, it should explain a
  non-obvious choice or work around a quirk — never restate what
  the code says.

## Validation

- `bash tests/smoke-test.sh <head-host> <port>` must pass against
  any deployed instance before merging.
- The launcher `recipe/scripts/start-tp2.sh` is idempotent — re-runs
  detect the running containers and exit 0 without restarting them.

## Pull-request hygiene

- One logical change per commit.
- PR description includes:
  - What changed (specific files / behavior)
  - Why (the reasoning, with link to upstream if applicable)
  - How tested (the smoke-test output, or a manual repro recipe)
- AGENTS.md update is **NOT** required for ADR-style changes —
  this is a recipe, not a decision record. ADRs in this repo live
  under `docs/adr/` (currently empty; add when warranted).

## See also

- `README.md` — recipe overview, including the upstream attribution table
