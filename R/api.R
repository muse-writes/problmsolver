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
  if (!is.null(envname)) {
    ps_use_backend_env(envname = envname, required = FALSE)
  }

  if (!is.null(python)) {
    use_python(python, required = TRUE)
  }

  ok <- py_module_available('problm_solver')

  if (!ok && isTRUE(auto_create)) {
    target_env <- if (is.null(envname)) 'r-problmsolver' else envname
    ps_backend_setup(envname = target_env)
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
  py_module_available('problm_solver')
}


#' Create/update a managed backend virtualenv
#'
#' Creates an isolated virtualenv and installs `problm-solver` so end users do
#' not need to manually manage Python setup.
#'
#' @param envname Virtualenv name managed by `reticulate`.
#' @param python Optional Python executable used to create the env.
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
  if (!virtualenv_exists(envname)) {
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
#' @param python Optional Python executable used to create env if missing.
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
  .problmsolver_env$module <- import('problm_solver', delay_load = delay_load)
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


# Sampler constructors -----------------------------------------------------

#' Create Python `MetropolisSampler`
#'
#' @param equil_branches Burn-in branch count.
#' @param max_branches Maximum number of branch samples.
#' @param tolerance Convergence tolerance.
#'
#' @return Python sampler object.
#' @export
ps_metropolis_sampler <- function(equil_branches = 5L, max_branches = 30L, tolerance = 1e-1) {
  ps_module()$adjust_probs$MetropolisSampler(
    equil_branches = as.integer(equil_branches),
    max_branches = as.integer(max_branches),
    tolerance = as.numeric(tolerance)
  )
}


#' Create Python `BeamSampler`
#'
#' @param beam_width Number of active beams retained per depth.
#' @param branch_top_k Number of next-token candidates expanded per beam.
#'
#' @return Python sampler object.
#' @export
ps_beam_sampler <- function(beam_width = 10L, branch_top_k = 5L) {
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


#' Wrap an R sampling function as a Python-compatible adjust function
#'
#' Converts an R function into a Python callable suitable for
#' `ps_generate_adjusted(..., adjust_fn = ...)`.
#'
#' The R function must accept one argument `ctx`, a list with fields:
#' - `token_probs`: named numeric vector of token log-probabilities
#' - `prev_probs`: numeric vector of previously selected token probabilities
#' - `context_tokens`: integer vector of current token IDs
#'
#' The function must return either:
#' - a named numeric vector, or
#' - a named list of numeric values
#'
#' representing adjusted token log-probabilities.
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
    r_ctx <- list(
      token_probs = as.numeric(unlist(py_to_r(ctx$token_probs))),
      prev_probs = as.numeric(py_to_r(ctx$prev_probs)),
      context_tokens = as.integer(py_to_r(ctx$context_tokens))
    )
    names(r_ctx$token_probs) <- names(py_to_r(ctx$token_probs))

    out <- fn(r_ctx)

    if (is.numeric(out)) {
      if (is.null(names(out))) {
        stop('R adjust function must return named numeric output.', call. = FALSE)
      }
      out_list <- as.list(as.numeric(out))
      names(out_list) <- names(out)
      return(out_list)
    }

    if (is.list(out)) {
      if (is.null(names(out))) {
        stop('R adjust function must return a named list.', call. = FALSE)
      }
      out_vals <- vapply(out, function(x) as.numeric(x)[1], numeric(1))
      out_list <- as.list(out_vals)
      names(out_list) <- names(out)
      return(out_list)
    }

    stop('R adjust function must return named numeric vector or named list.', call. = FALSE)
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
#'
#' @return An object of class `ps_model` containing the Python model object.
#' @export
ps_model <- function(
    fname,
    context = '',
    n_ctx = 4096L,
    logits_all = FALSE,
    n_gpu_layers = 0L
) {
  py_model <- ps_module()$llama_interface$ModelInstance(
    fname = fname,
    context = context,
    n_ctx = as.integer(n_ctx),
    logits_all = isTRUE(logits_all),
    n_gpu_layers = as.integer(n_gpu_layers)
  )

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
#'
#' @return Character scalar response.
#' @export
ps_query <- function(model) {
  .assert_model(model)
  py_to_r(model$py$query())
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


#' Query token probabilities for one generated response
#'
#' @param model A `ps_model`.
#'
#' @return Named list containing prompt, tokens, and probs.
#' @export
ps_query_log_probs <- function(model) {
  .assert_model(model)
  out <- model$py$query_log_probs()
  list(
    prompt = py_to_r(out$prompt),
    tokens = py_to_r(out$tokens),
    probs = py_to_r(out$probs)
  )
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
    branch_sampler = NULL
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

  out <- do.call(model$py$generate_adjusted, kwargs)

  list(
    context = py_to_r(out$context),
    hyperparams = py_to_r(out$hyperparams),
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
.assert_model <- function(model) {
  if (!inherits(model, 'ps_model') || is.null(model$py)) {
    stop('`model` must be an object returned by ps_model().', call. = FALSE)
  }
}
