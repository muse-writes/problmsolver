# problmsolver (R)

`problmsolver` is an R wrapper around the Python package `problm_solver`, using
`reticulate` as the bridge.

## Installation

From this package directory:

```r
# install.packages("remotes")
remotes::install_local(".")
```

## Quick start

```r
library(problmsolver)

# One-time setup for a managed Python backend env
# (prefers python3.13 automatically when available)
ps_backend_setup()

# Optional: inspect active Python configuration
ps_python_config()

# Import backend module
ps_module()
```

## Alternate backend setup (local `probLM-solver` clone)

If `probLM-solver` is not hosted on PyPI for your workflow and you have it
cloned locally, install from that path into the managed backend env:

```r
ps_backend_setup_local("/abs/path/to/probLM-solver")
ps_use_backend_env("r-problmsolver")
ps_module()
```

## Create a model

```r
model <- ps_model(
  fname = "/path/to/model.gguf",
  context = "Why is the sky blue?",
  n_ctx = 4096L,
  logits_all = TRUE,
  n_gpu_layers = 999L,
  use_c_api = TRUE,
  c_api_copy_logits = TRUE,
  rng = 123L
)
```

## Sample a single adjusted token (live-state friendly)

```r
# Uses model's live state by default (no prompt rebuild when live state exists)
one <- ps_sample_token_adjusted(
  model = model,
  top_k = 8L,
  top_p = 0.9,
  adjust_fn = ps_sample_low_temp(alpha = 2.0)
)

str(one)
```

## Generate with built-in samplers

```r
# Low temperature
low_temp <- ps_sample_low_temp(alpha = 2.0)
out_low <- ps_generate_adjusted(
  model = model,
  top_k = 8L,
  top_p = 0.9,
  adjust_fn = low_temp,
  max_tokens = 128L
)

# Power distribution + Metropolis
metropolis <- ps_metropolis_sampler(equil_branches = 1L, max_branches = 10L)
power <- ps_sample_power_dist(alpha = 2.0, lookahead_depth = 10L, branch_sampler = metropolis)
out_power <- ps_generate_adjusted(
  model = model,
  top_k = 8L,
  top_p = 0.9,
  adjust_fn = power,
  max_tokens = 128L
)
```

## Custom sampling function example

You can define a sampling function directly in R and wrap it for Python with
`ps_r_adjust_fn()`. The Python backend now adjusts candidates in token-ID space,
so the R function receives candidate IDs and log-probabilities and returns
adjusted log-probabilities for those IDs.

```r
my_adjust_r <- function(ctx) {
  # `ctx$candidates` has token_id, logprob, and candidate_prob columns.
  out <- ctx$logprobs

  # example: slightly favour the first candidate
  out[1] <- out[1] + 0.25

  # unnamed numeric output keeps the original candidate token_id order
  out
}

out_custom <- ps_generate_adjusted(
  model = model,
  top_k = 8L,
  top_p = 0.9,
  adjust_fn = ps_r_adjust_fn(my_adjust_r),
  max_tokens = 128L
)
```

## Managed backend behavior

Users do **not** need to manually install Python backend dependencies if they use:

- `ps_backend_setup()` to create/install a managed virtualenv (prefers `python3.13` by default)
- `ps_backend_setup_local()` to install backend from a local clone path
- `ps_use_backend_env()` to activate it in future sessions
- `ps_configure(auto_create = TRUE)` to lazily create backend when missing

Example:

```r
ps_configure(envname = "r-problmsolver", auto_create = TRUE)
```

## Notes for package checks / CI

Automatic backend creation can be undesirable in strict CI or CRAN-like checks.
In those contexts, prefer explicit setup in advance and use non-failing probes:

```r
ps_configure(required = FALSE)
ps_available()
```

## API overview

- Backend/session: `ps_configure()`, `ps_available()`, `ps_module()`, `ps_reset_module()`
- Model: `ps_model()`, `ps_query()`, `ps_query_n_times()`, `ps_generate_data()`, `ps_query_log_probs()`
- Next-token/branch probes: `ps_query_log_probs_next_token_ids()`, `ps_query_log_probs_next_token()`, `ps_query_branch()`, `ps_query_branch_from_live()`
- Adjusted gen: `ps_sample_token_adjusted()`, `ps_generate_adjusted()`, `ps_test_dataset_adjusted()`
- Samplers/randomness: `ps_random()`, `ps_metropolis_sampler()`, `ps_beam_sampler()`, `ps_sample_low_temp()`, `ps_sample_power_dist()`, `ps_adjust_identity()`, `ps_r_adjust_fn()`
- Datasets: `ps_get_math500()`, `ps_get_problems_math500()`
