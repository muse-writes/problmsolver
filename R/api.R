#' R API for the Python `problm_solver` backend
#'
#' This package provides a thin, explicit wrapper around the Python package
#' `problm_solver` using `reticulate`.
#'
#' @importFrom reticulate import py_module_available py_config py_func use_python use_virtualenv
#' @importFrom reticulate py_to_r virtualenv_create virtualenv_exists virtualenv_install
NULL


# Internal module cache ----------------------------------------------------
.problmsolver_env <- new.env(parent = emptyenv())
.problmsolver_env$module <- NULL


#' Configure Python interpreter for `reticulate`
#'
#' Optionally force a specific Python executable before importing
#' `problm_solver`.
#'
#' @param python Optional path to Python executable.
#' @param envname Optional reticulate virtualenv name to activate first.
#' @param auto_create If `TRUE`, create/install the managed backend env when
#'   `problm_solver` is missing.
#' @param required If `TRUE`, error if the Python module cannot be imported.
#'
#' @return Invisibly returns `TRUE` if module is importable.
#' @export
ps_configure <- function(
    python = NULL,
    envname = NULL,
    auto_create = FALSE,
    required = TRUE
) {
  explicit_python <- !is.null(python)
  python <- if (is.null(python)) .ps_default_python() else python

  if (!is.null(envname)) {
    ps_use_backend_env(envname = envname, required = FALSE)
  }

  .ps_bind_python_preferred(python, warn_mismatch = explicit_python)

  ok <- py_module_available('problm_solver')

  if (!ok && isTRUE(auto_create)) {
    target_env <- if (is.null(envname)) 'r-problmsolver' else envname
    ps_backend_setup(envname = target_env, python = python)
    ok <- py_module_available('problm_solver')
  }

  if (!ok && isTRUE(required)) {
    stop(
      'Python module `problm_solver` is not available in the active reticulate environment. ',
      'Run `ps_backend_setup()` for a managed environment, or install manually ',
      '(e.g. `pip install problm-solver`).',
      call. = FALSE
    )
  }

  invisible(ok)
}


#' Check whether Python backend is available
#'
#' @return Logical scalar indicating whether `problm_solver` is importable.
#' @export
ps_available <- function() {
  .ps_bind_python_preferred(.ps_default_python(), warn_mismatch = FALSE)
  py_module_available('problm_solver')
}


#' Create/update a managed backend virtualenv
#'
#' Creates an isolated virtualenv and installs `problm-solver` so end users do
#' not need to manually manage Python setup.
#'
#' @param envname Virtualenv name managed by `reticulate`.
#' @param python Optional Python executable used to create the env. If `NULL`,
#'   the wrapper will prefer `python3.13` when available on `PATH`.
#' @param packages Python packages to install.
#' @param upgrade If `TRUE`, force reinstall of packages.
#'
#' @return Invisibly returns `envname`.
#' @export
ps_backend_setup <- function(
    envname = 'r-problmsolver',
    python = NULL,
    packages = c('problm-solver'),
    upgrade = FALSE
) {
  if (is.null(python)) {
    python <- .ps_default_python()
  }

  if (virtualenv_exists(envname)) {
    env_python <- tryCatch(reticulate::virtualenv_python(envname), error = function(e) NULL)
    env_version <- .ps_python_version(env_python)
    requested_version <- .ps_python_version(python)

    if (!is.null(requested_version) && .ps_is_python_313(requested_version) &&
        !is.null(env_version) && !.ps_is_python_313(env_version)) {
      warning(
        'Virtualenv `', envname, '` already exists with ', env_version,
        ', not Python 3.13. To recreate with Python 3.13 run ',
        '`reticulate::virtualenv_remove("', envname, '")` then `ps_backend_setup(...)`.',
        call. = FALSE
      )
    }
  } else {
    virtualenv_create(envname = envname, python = python)
  }

  virtualenv_install(
    envname = envname,
    packages = packages,
    ignore_installed = !isTRUE(upgrade)
  )

  use_virtualenv(envname, required = TRUE)
  ps_reset_module()
  invisible(envname)
}


#' Activate a managed backend virtualenv
#'
#' @param envname Virtualenv name.
#' @param required Passed to `reticulate::use_virtualenv()`.
#'
#' @return Invisibly returns `envname`.
#' @export
ps_use_backend_env <- function(envname = 'r-problmsolver', required = TRUE) {
  use_virtualenv(envname, required = required)
  ps_reset_module()
  invisible(envname)
}


#' Setup backend from a local `probLM-solver` clone
#'
#' Convenience wrapper for users who have `probLM-solver` cloned locally rather
#' than installed from an index.
#'
#' @param path Path to local `probLM-solver` repository.
#' @param envname Managed virtualenv name.
#' @param python Optional Python executable used to create env if missing. If
#'   `NULL`, the wrapper will prefer `python3.13` when available on `PATH`.
#' @param upgrade If `TRUE`, force reinstall in backend env.
#'
#' @return Invisibly returns `envname`.
#' @export
ps_backend_setup_local <- function(
    path,
    envname = 'r-problmsolver',
    python = NULL,
    upgrade = FALSE
) {
  if (!nzchar(path) || !dir.exists(path)) {
    stop('`path` must be an existing directory to a local probLM-solver clone.', call. = FALSE)
  }

  local_path <- normalizePath(path, winslash = '/', mustWork = TRUE)
  ps_backend_setup(
    envname = envname,
    python = python,
    packages = c(local_path),
    upgrade = upgrade
  )
}


#' Return active reticulate Python configuration
#'
#' @return A list-like Python configuration from `reticulate::py_config()`.
#' @export
ps_python_config <- function() {
  py_config()
}


#' Import and cache the Python `problm_solver` module
#'
#' @param delay_load Passed to `reticulate::import()`.
#'
#' @return Python module proxy.
#' @export
ps_module <- function(delay_load = FALSE) {
  if (!is.null(.problmsolver_env$module)) {
    return(.problmsolver_env$module)
  }

  ps_configure(required = TRUE)
  root <- import('problm_solver', delay_load = delay_load)
  root$adjust_probs <- import('problm_solver.adjust_probs', delay_load = delay_load)
  root$candidates <- import('problm_solver.candidates', delay_load = delay_load)
  root$datasets <- import('problm_solver.datasets', delay_load = delay_load)
  root$llama_interface <- import('problm_solver.llama_interface', delay_load = delay_load)
  .problmsolver_env$module <- root
  .problmsolver_env$module
}


#' Clear cached Python module reference
#'
#' Useful when switching interpreters/environments in the same R session.
#'
#' @return Invisible `NULL`.
#' @export
ps_reset_module <- function() {
  .problmsolver_env$module <- NULL
  invisible(NULL)
}


# Randomness ---------------------------------------------------------------

#' Create a backend random manager
#'
#' A random manager is an opaque backend object that can be passed to `rng`
#' arguments on model/sampler/query functions to get reproducible named random
#' streams. Numeric seeds can also be passed directly to `rng` arguments.
#'
#' @param seed Integer root seed.
#'
#' @return Python `RandomManager` object.
#' @export
ps_random <- function(seed = 314159L) {
  ps_module()$PSRandom(seed = as.integer(seed))
}


# Sampler constructors -----------------------------------------------------

#' Create Python `MetropolisSampler`
#'
#' @param equil_branches Burn-in branch count.
#' @param max_branches Maximum number of branch samples.
#' @param tolerance Convergence tolerance.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return Python sampler object.
#' @export
ps_metropolis_sampler <- function(
    equil_branches = 5L,
    max_branches = 30L,
    tolerance = 1e-1,
    rng = NULL
) {
  kwargs <- list(
    equil_branches = as.integer(equil_branches),
    max_branches = as.integer(max_branches),
    tolerance = as.numeric(tolerance)
  )
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)
  do.call(ps_module()$adjust_probs$MetropolisSampler, kwargs)
}


#' Create Python `BeamSampler`
#'
#' @param beam_width Number of active beams retained per depth.
#' @param branch_top_k Number of next-token candidates expanded per beam.
#'
#' @return Python sampler object.
#' @export
ps_beam_sampler <- function(beam_width = 3L, branch_top_k = 5L) {
  ps_module()$adjust_probs$BeamSampler(
    beam_width = as.integer(beam_width),
    branch_top_k = as.integer(branch_top_k)
  )
}


#' Create Python `SampleLowTemp`
#'
#' @param alpha Temperature-power parameter.
#'
#' @return Python callable sampling object.
#' @export
ps_sample_low_temp <- function(alpha) {
  ps_module()$adjust_probs$SampleLowTemp(alpha = as.numeric(alpha))
}


#' Create Python `SamplePowerDist`
#'
#' @param alpha Power parameter.
#' @param lookahead_depth Number of lookahead tokens per branch.
#' @param branch_sampler Python branch sampler object. If `NULL`, a
#'   `MetropolisSampler(max_branches = 10)` is created.
#'
#' @return Python callable sampling object.
#' @export
ps_sample_power_dist <- function(alpha, lookahead_depth = 10L, branch_sampler = NULL) {
  if (is.null(branch_sampler)) {
    branch_sampler <- ps_metropolis_sampler(max_branches = 10L)
  }
  ps_module()$adjust_probs$SamplePowerDist(
    alpha = as.numeric(alpha),
    lookahead_depth = as.integer(lookahead_depth),
    branch_sampler = branch_sampler
  )
}


#' Python `adjust_identity` sampling function
#'
#' @return Python callable.
#' @export
ps_adjust_identity <- function() {
  ps_module()$adjust_probs$adjust_identity
}


#' Wrap an R adjustment function for adjusted generation
#'
#' Converts an R function into a Python-compatible `AdjustFn` for
#' `ps_generate_adjusted()` and `ps_sample_token_adjusted()`. The current Python
#' backend adjusts candidates in token-ID space, so the R callback receives and
#' returns token IDs plus log-probabilities.
#'
#' The R callback receives one list `ctx` with fields:
#' - `candidates`: data frame with `token_id`, `logprob`, and `candidate_prob`
#' - `token_ids`: integer vector of candidate token IDs
#' - `logprobs`: numeric vector of candidate log-probabilities
#' - `prev_probs`: numeric vector of previous sampled token probabilities
#' - `context_tokens`: integer vector of current prompt/generated token IDs
#' - `query_next_ids(context_tokens)`: helper returning a candidate data frame
#' - `query_branch(context_tokens, depth)`: helper returning a branch log-prob
#'
#' The callback may return a data frame with `token_id`/`logprob` columns, a
#' list with `token_ids`/`logprobs`, a named numeric vector whose names are token
#' IDs, or an unnamed numeric vector of the same length/order as the input
#' candidates.
#'
#' @param fn R function implementing adjustment logic.
#'
#' @return Python callable.
#' @export
ps_r_adjust_fn <- function(fn) {
  if (!is.function(fn)) {
    stop('`fn` must be a function.', call. = FALSE)
  }

  py_func(function(ctx) {
    candidates <- .ps_candidate_tokens_to_df(ctx$token_id_probs)
    token_ids <- candidates$token_id
    logprobs <- candidates$logprob

    r_ctx <- list(
      candidates = candidates,
      token_ids = token_ids,
      logprobs = logprobs,
      prev_probs = as.numeric(py_to_r(ctx$prev_probs)),
      context_tokens = as.integer(py_to_r(ctx$context_tokens)),
      query_next_ids = function(context_tokens) {
        .ps_candidate_tokens_to_df(ctx$query_next_id(as.list(as.integer(context_tokens))))
      },
      query_branch = function(context_tokens, depth) {
        as.numeric(ctx$query_branch(as.list(as.integer(context_tokens)), as.integer(depth)))[1]
      }
    )

    out <- fn(r_ctx)
    converted <- .ps_r_adjust_output_to_candidates(out, token_ids = token_ids)
    .ps_candidate_tokens(converted$token_ids, converted$logprobs)
  })
}


# Model wrapper ------------------------------------------------------------

#' Create a `problm_solver` model instance
#'
#' @param fname Path to GGUF model file.
#' @param context Initial prompt/context.
#' @param n_ctx Context window size.
#' @param logits_all Whether full logits should be available.
#' @param n_gpu_layers Number of layers to offload to GPU.
#' @param use_c_api Whether to use the backend C API wrapper for logits/state.
#' @param c_api_copy_logits Whether C-API logits should be copied before use.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return An object of class `ps_model` containing the Python model object.
#' @export
ps_model <- function(
    fname,
    context = '',
    n_ctx = 4096L,
    logits_all = FALSE,
    n_gpu_layers = 0L,
    use_c_api = TRUE,
    c_api_copy_logits = TRUE,
    rng = NULL
) {
  kwargs <- list(
    fname = fname,
    context = context,
    n_ctx = as.integer(n_ctx),
    logits_all = isTRUE(logits_all),
    n_gpu_layers = as.integer(n_gpu_layers),
    use_c_api = isTRUE(use_c_api),
    c_api_copy_logits = isTRUE(c_api_copy_logits)
  )
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)

  py_model <- do.call(ps_module()$llama_interface$ModelInstance, kwargs)
  structure(list(py = py_model), class = 'ps_model')
}


#' @export
print.ps_model <- function(x, ...) {
  cat('<ps_model>\n')
  cat('  Python type:', class(x$py)[1], '\n')
  invisible(x)
}


#' Change model context
#'
#' @param model A `ps_model`.
#' @param context New context string.
#'
#' @return Invisibly returns `model`.
#' @export
ps_change_context <- function(model, context) {
  .assert_model(model)
  model$py$change_context(context)
  invisible(model)
}


#' Query model once
#'
#' @param model A `ps_model`.
#' @param max_tokens Maximum generated tokens.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return Character scalar response.
#' @export
ps_query <- function(model, max_tokens = 512L, rng = NULL) {
  .assert_model(model)
  kwargs <- list(max_tokens = as.integer(max_tokens))
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)
  py_to_r(do.call(model$py$query, kwargs))
}


#' Query model multiple times
#'
#' @param model A `ps_model`.
#' @param n Number of responses.
#'
#' @return Character vector of responses.
#' @export
ps_query_n_times <- function(model, n) {
  .assert_model(model)
  py_to_r(model$py$query_n_times(as.integer(n)))
}


#' Generate response data with repeated ordinary queries
#'
#' @param model A `ps_model`.
#' @param n_samples Number of responses.
#'
#' @return Plain R list with `prompt` and `data` fields.
#' @export
ps_generate_data <- function(model, n_samples) {
  .assert_model(model)
  out <- model$py$generate_data(as.integer(n_samples))
  list(
    prompt = py_to_r(out$prompt),
    data = py_to_r(out$data)
  )
}


#' Query token probabilities for one generated response
#'
#' @param model A `ps_model`.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return Named list containing prompt, tokens, and probs.
#' @export
ps_query_log_probs <- function(model, rng = NULL) {
  .assert_model(model)
  kwargs <- list()
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)
  out <- do.call(model$py$query_log_probs, kwargs)
  list(
    prompt = py_to_r(out$prompt),
    tokens = py_to_r(out$tokens),
    probs = py_to_r(out$probs)
  )
}


#' Query top-k next-token candidates in token-ID space
#'
#' @param model A `ps_model`.
#' @param context_tokens Integer vector of token IDs to evaluate.
#' @param n_tokens Number of candidate tokens to return.
#'
#' @return Data frame with `token_id`, `logprob`, and `candidate_prob`.
#' @export
ps_query_log_probs_next_token_ids <- function(model, context_tokens, n_tokens) {
  .assert_model(model)
  out <- model$py$query_log_probs_next_token_ids(
    context_tokens = as.list(as.integer(context_tokens)),
    n_tokens = as.integer(n_tokens)
  )
  .ps_candidate_tokens_to_df(out)
}


#' Query top-k next-token candidates as strings
#'
#' @param model A `ps_model`.
#' @param context_tokens Integer vector of token IDs to evaluate.
#' @param n_tokens Number of candidate tokens to return.
#'
#' @return Named list containing prompt, output token IDs, and top-k token map.
#' @export
ps_query_log_probs_next_token <- function(model, context_tokens, n_tokens) {
  .assert_model(model)
  out <- model$py$query_log_probs_next_token(
    context_tokens = as.list(as.integer(context_tokens)),
    n_tokens = as.integer(n_tokens)
  )
  list(
    prompt = py_to_r(out$prompt),
    output_vec = as.integer(py_to_r(out$output_vec)),
    top_k_tokens = py_to_r(out$top_k_tokens)
  )
}


#' Generate a random branch and return its total log-probability
#'
#' @param model A `ps_model`.
#' @param context_tokens Integer vector of token IDs to evaluate before branch generation.
#' @param max_tokens Maximum branch length.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return Numeric scalar branch log-probability.
#' @export
ps_query_branch <- function(model, context_tokens, max_tokens, rng = NULL) {
  .assert_model(model)
  kwargs <- list(
    context_tokens = as.list(as.integer(context_tokens)),
    max_tokens = as.integer(max_tokens)
  )
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)
  as.numeric(do.call(model$py$query_branch, kwargs))[1]
}


#' Generate a random branch from the model's current live state
#'
#' This is a thin wrapper over Python `query_branch_from_live()`. It is mainly
#' useful for advanced iterative decoding workflows that deliberately manage the
#' model's live state through previous calls such as `ps_sample_token_adjusted()`.
#'
#' @param model A `ps_model`.
#' @param max_tokens Maximum branch length.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return Numeric scalar branch log-probability.
#' @export
ps_query_branch_from_live <- function(model, max_tokens, rng = NULL) {
  .assert_model(model)
  kwargs <- list(max_tokens = as.integer(max_tokens))
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)
  as.numeric(do.call(model$py$query_branch_from_live, kwargs))[1]
}


#' Sample one adjusted token from the current model state
#'
#' Wrapper around Python `ModelInstance.sample_token_adjusted()`.
#'
#' @param model A `ps_model`.
#' @param top_k Top-k candidate count.
#' @param top_p Top-p mass threshold.
#' @param adjust_fn Python callable adjustment function.
#' @param use_live_state If `TRUE`, use current live model state when available.
#' @param context_tokens Optional explicit context token IDs used when rebuilding state.
#' @param prev_probs Optional numeric vector of previously sampled token probabilities.
#' @param commit_token If `TRUE`, append sampled non-terminal token to live state.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return A named list mirroring Python `sample_token_adjusted()` output.
#' @export
ps_sample_token_adjusted <- function(
    model,
    top_k,
    top_p,
    adjust_fn,
    use_live_state = TRUE,
    context_tokens = NULL,
    prev_probs = NULL,
    commit_token = TRUE,
    rng = NULL
) {
  .assert_model(model)

  kwargs <- list(
    top_k = as.integer(top_k),
    top_p = as.numeric(top_p),
    adjust_fn = adjust_fn,
    use_live_state = isTRUE(use_live_state),
    commit_token = isTRUE(commit_token)
  )

  if (!is.null(context_tokens)) kwargs$context_tokens <- as.list(as.integer(context_tokens))
  if (!is.null(prev_probs)) kwargs$prev_probs <- as.list(as.numeric(prev_probs))
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)

  py_to_r(do.call(model$py$sample_token_adjusted, kwargs))
}


#' Generate adjusted response data
#'
#' @param model A `ps_model`.
#' @param top_k Top-k candidate count.
#' @param top_p Top-p mass threshold.
#' @param adjust_fn Python callable adjustment function.
#' @param max_tokens Max generated tokens.
#' @param alpha Optional alpha for metadata.
#' @param sampling_method Optional sampling method label.
#' @param branch_sampler Optional branch sampler label.
#' @param rng Optional numeric seed or backend random manager.
#'
#' @return A list with fields mirroring Python `LLMOutputDataFull`.
#' @export
ps_generate_adjusted <- function(
    model,
    top_k,
    top_p,
    adjust_fn,
    max_tokens,
    alpha = 1.0,
    sampling_method = NULL,
    branch_sampler = NULL,
    rng = NULL
) {
  .assert_model(model)

  kwargs <- list(
    top_k = as.integer(top_k),
    top_p = as.numeric(top_p),
    adjust_fn = adjust_fn,
    max_tokens = as.integer(max_tokens),
    alpha = as.numeric(alpha)
  )

  if (!is.null(sampling_method)) kwargs$sampling_method <- sampling_method
  if (!is.null(branch_sampler)) kwargs$branch_sampler <- branch_sampler
  if (!is.null(rng)) kwargs$rng <- .ps_rng_arg(rng)

  out <- do.call(model$py$generate_adjusted, kwargs)

  list(
    context = py_to_r(out$context),
    hyperparams = .ps_hyperparams_to_list(out$hyperparams),
    response_probabilities = py_to_r(out$response_probabilities),
    response_topk = py_to_r(out$response_topk),
    sampling_method = py_to_r(out$sampling_method),
    branch_sampler = py_to_r(out$branch_sampler)
  )
}


#' Evaluate adjusted generation over a dataset
#'
#' @param model A `ps_model`.
#' @param dataset Character vector/list of prompts.
#' @param top_k Top-k candidate count.
#' @param top_p Top-p mass threshold.
#' @param adjust_fn Python callable adjustment function.
#' @param max_tokens Max generated tokens.
#'
#' @return Character vector of generated answers.
#' @export
ps_test_dataset_adjusted <- function(model, dataset, top_k, top_p, adjust_fn, max_tokens) {
  .assert_model(model)
  py_to_r(model$py$test_dataset_adjusted(
    dataset = as.list(dataset),
    top_k = as.integer(top_k),
    top_p = as.numeric(top_p),
    adjust_fn = adjust_fn,
    max_tokens = as.integer(max_tokens)
  ))
}


# Datasets -----------------------------------------------------------------

#' Load MATH500 dataset from Python backend
#'
#' @param fname Optional local file path.
#'
#' @return Data frame.
#' @export
ps_get_math500 <- function(fname = NULL) {
  datasets <- ps_module()$datasets
  if (is.null(fname)) {
    py_to_r(datasets$get_math500())
  } else {
    py_to_r(datasets$get_math500(fname = fname))
  }
}


#' Load MATH500 problem strings
#'
#' @param fname Optional local file path.
#'
#' @return Character vector of problems.
#' @export
ps_get_problems_math500 <- function(fname = NULL) {
  datasets <- ps_module()$datasets
  if (is.null(fname)) {
    py_to_r(datasets$get_problems_math500())
  } else {
    py_to_r(datasets$get_problems_math500(fname = fname))
  }
}


# Helpers ------------------------------------------------------------------
.ps_default_python <- function() {
  py313 <- Sys.which('python3.13')
  if (nzchar(py313)) {
    return(py313)
  }

  uv_candidates <- unique(c(
    Sys.which('uv'),
    path.expand('~/.local/bin/uv'),
    '/usr/local/bin/uv'
  ))
  uv_candidates <- uv_candidates[nzchar(uv_candidates) & file.exists(uv_candidates)]

  for (uv in uv_candidates) {
    uv_out <- tryCatch(
      system2(uv, c('python', 'find', '3.13'), stdout = TRUE, stderr = FALSE),
      error = function(e) character(0)
    )
    if (length(uv_out) >= 1 && nzchar(uv_out[[1]]) && file.exists(uv_out[[1]])) {
      return(uv_out[[1]])
    }
  }

  uv_glob <- Sys.glob(path.expand('~/.local/share/uv/python/*/bin/python3.13'))
  if (length(uv_glob) >= 1 && nzchar(uv_glob[[1]]) && file.exists(uv_glob[[1]])) {
    return(uv_glob[[1]])
  }

  NULL
}

.ps_bind_python_preferred <- function(python, warn_mismatch = TRUE) {
  if (is.null(python) || !nzchar(python) || !file.exists(python)) {
    return(invisible(NULL))
  }

  if (reticulate::py_available(initialize = FALSE)) {
    cfg <- tryCatch(py_config(), error = function(e) NULL)
    active_python <- if (is.null(cfg)) NULL else cfg$python

    if (!is.null(active_python) && nzchar(active_python)) {
      same <- tryCatch(
        normalizePath(active_python, winslash = '/', mustWork = FALSE) ==
          normalizePath(python, winslash = '/', mustWork = FALSE),
        error = function(e) FALSE
      )
      if (!same && isTRUE(warn_mismatch)) {
        warning(
          'reticulate is already initialized with ', active_python,
          '. Preferred Python is ', python,
          '. Restart R to switch interpreters.',
          call. = FALSE
        )
      }
    }
    return(invisible(NULL))
  }

  use_python(python, required = FALSE)
  invisible(NULL)
}

.ps_python_version <- function(python) {
  if (is.null(python) || !nzchar(python)) {
    return(NULL)
  }

  out <- tryCatch(
    system2(python, '--version', stdout = TRUE, stderr = TRUE),
    error = function(e) character(0)
  )

  if (length(out) < 1 || !nzchar(out[[1]])) {
    return(NULL)
  }

  out[[1]]
}

.ps_is_python_313 <- function(version_string) {
  !is.null(version_string) && grepl('^Python 3\\.13\\.', version_string)
}

.assert_model <- function(model) {
  if (!inherits(model, 'ps_model') || is.null(model$py)) {
    stop('`model` must be an object returned by ps_model().', call. = FALSE)
  }
}

.ps_rng_arg <- function(rng) {
  if (is.numeric(rng) && length(rng) == 1L) {
    return(as.integer(rng))
  }
  rng
}

.ps_candidate_tokens <- function(token_ids, logprobs) {
  np <- import('numpy', convert = FALSE)
  ps_module()$candidates$CandidateTokens(
    candidate_ids = np$array(as.list(as.integer(token_ids)), dtype = 'int32'),
    candidate_logprobs = np$array(as.list(as.numeric(logprobs)), dtype = 'float64')
  )
}

.ps_candidate_tokens_to_df <- function(candidates) {
  token_ids <- as.integer(py_to_r(candidates$candidate_ids))
  logprobs <- as.numeric(py_to_r(candidates$candidate_logprobs))
  if (length(logprobs) == 0L) {
    probs <- numeric(0)
  } else {
    shifted <- logprobs - max(logprobs)
    probs <- exp(shifted) / sum(exp(shifted))
  }
  data.frame(
    token_id = token_ids,
    logprob = logprobs,
    candidate_prob = probs,
    stringsAsFactors = FALSE
  )
}

.ps_r_adjust_output_to_candidates <- function(out, token_ids) {
  if (is.data.frame(out)) {
    if (!all(c('token_id', 'logprob') %in% names(out))) {
      stop('R adjust data frame output must contain `token_id` and `logprob` columns.', call. = FALSE)
    }
    return(list(token_ids = as.integer(out$token_id), logprobs = as.numeric(out$logprob)))
  }

  if (is.list(out) && all(c('token_ids', 'logprobs') %in% names(out))) {
    return(list(token_ids = as.integer(out$token_ids), logprobs = as.numeric(out$logprobs)))
  }

  if (is.numeric(out)) {
    if (!is.null(names(out)) && all(nzchar(names(out)))) {
      return(list(token_ids = as.integer(names(out)), logprobs = as.numeric(out)))
    }

    if (length(out) != length(token_ids)) {
      stop(
        'Unnamed numeric adjust output must have same length as input candidates.',
        call. = FALSE
      )
    }
    return(list(token_ids = as.integer(token_ids), logprobs = as.numeric(out)))
  }

  stop(
    'R adjust function must return a data frame, a token_ids/logprobs list, ',
    'a named numeric vector, or an unnamed numeric vector matching the input length.',
    call. = FALSE
  )
}

.ps_hyperparams_to_list <- function(hyperparams) {
  if (is.list(hyperparams) && all(c('alpha', 'top_k', 'top_p', 'max_tokens') %in% names(hyperparams))) {
    return(hyperparams)
  }

  list(
    alpha = as.numeric(py_to_r(hyperparams$alpha)),
    top_k = as.integer(py_to_r(hyperparams$top_k)),
    top_p = as.numeric(py_to_r(hyperparams$top_p)),
    max_tokens = as.integer(py_to_r(hyperparams$max_tokens))
  )
}
