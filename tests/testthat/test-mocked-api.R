.ps_ns <- asNamespace('problmsolver')
.ps_env <- get('.problmsolver_env', envir = .ps_ns)

test_that('sampler constructors call through mocked python module', {
  fake <- new.env(parent = emptyenv())
  fake$adjust_probs <- new.env(parent = emptyenv())

  fake$adjust_probs$MetropolisSampler <- function(equil_branches, max_branches, tolerance) {
    list(kind = 'metropolis', equil_branches = equil_branches, max_branches = max_branches,
         tolerance = tolerance)
  }
  fake$adjust_probs$BeamSampler <- function(beam_width, branch_top_k) {
    list(kind = 'beam', beam_width = beam_width, branch_top_k = branch_top_k)
  }
  fake$adjust_probs$SampleLowTemp <- function(alpha) list(kind = 'low_temp', alpha = alpha)
  fake$adjust_probs$SamplePowerDist <- function(alpha, lookahead_depth, branch_sampler) {
    list(kind = 'power', alpha = alpha, lookahead_depth = lookahead_depth,
         branch_sampler = branch_sampler)
  }
  fake$adjust_probs$adjust_identity <- 'identity_fn'

  old <- .ps_env$module
  on.exit(.ps_env$module <- old, add = TRUE)
  .ps_env$module <- fake

  m <- ps_metropolis_sampler(1L, 2L, 0.25)
  expect_equal(m$kind, 'metropolis')
  expect_equal(m$equil_branches, 1L)
  expect_equal(m$max_branches, 2L)

  b <- ps_beam_sampler(9L, 4L)
  expect_equal(b$kind, 'beam')
  expect_equal(b$beam_width, 9L)

  lt <- ps_sample_low_temp(2)
  expect_equal(lt$alpha, 2)

  p <- ps_sample_power_dist(3, 7L, branch_sampler = b)
  expect_equal(p$kind, 'power')
  expect_equal(p$lookahead_depth, 7L)

  expect_identical(ps_adjust_identity(), 'identity_fn')
})


test_that('model/query wrappers convert and return plain R objects', {
  fake <- new.env(parent = emptyenv())
  fake$llama_interface <- new.env(parent = emptyenv())

  py <- new.env(parent = emptyenv())
  py$change_context <- function(context) py$context <<- context
  py$query <- function() 'hello world'
  py$query_n_times <- function(n) rep('x', n)
  py$query_log_probs <- function() {
    out <- new.env(parent = emptyenv())
    out$prompt <- 'p'
    out$tokens <- c('a', 'b')
    out$probs <- c(0.3, 0.7)
    out
  }
  py$test_dataset_adjusted <- function(dataset, top_k, top_p, adjust_fn, max_tokens) {
    rep('ans', length(dataset))
  }

  py$sample_token_adjusted <- function(top_k, top_p, adjust_fn, use_live_state,
                                       context_tokens = NULL, prev_probs = NULL,
                                       commit_token = TRUE) {
    py$sample_token_adjusted_call <- list(
      top_k = top_k,
      top_p = top_p,
      adjust_fn = adjust_fn,
      use_live_state = use_live_state,
      context_tokens = context_tokens,
      prev_probs = prev_probs,
      commit_token = commit_token
    )

    list(
      state_source = if (isTRUE(use_live_state)) 'live' else 'prompt',
      used_live_state = isTRUE(use_live_state),
      top_k = top_k,
      top_p = top_p,
      candidates_before_adjustment = list(
        list(token = 'a', logprob = -0.1, prob = 0.7),
        list(token = 'b', logprob = -1.1, prob = 0.3)
      ),
      candidates_after_adjustment = list(
        list(token = 'a', logprob = -0.05, prob = 0.8),
        list(token = 'b', logprob = -1.4, prob = 0.2)
      ),
      sampled_token = list(token = 'a', token_ids = list(42L), logprob = -0.05, prob = 0.8),
      sampled_token_is_terminal = FALSE,
      context_tokens_used_for_eval = context_tokens
    )
  }

  py$generate_adjusted <- function(top_k, top_p, adjust_fn, max_tokens, alpha,
                                   sampling_method = NULL, branch_sampler = NULL) {
    out <- new.env(parent = emptyenv())
    out$context <- c('c1')
    out$hyperparams <- list(alpha = alpha, top_k = top_k, top_p = top_p, max_tokens = max_tokens)
    out$response_probabilities <- list(c('t'), c(0.9))
    out$response_topk <- list(c('t'), list(c(t = -0.1)))
    out$sampling_method <- if (is.null(sampling_method)) 'auto' else sampling_method
    out$branch_sampler <- branch_sampler
    out
  }

  fake$llama_interface$ModelInstance <- function(fname, context, n_ctx, logits_all, n_gpu_layers) {
    py$fname <- fname
    py$context <- context
    py$n_ctx <- n_ctx
    py$logits_all <- logits_all
    py$n_gpu_layers <- n_gpu_layers
    py
  }

  old <- .ps_env$module
  on.exit(.ps_env$module <- old, add = TRUE)
  .ps_env$module <- fake

  model <- ps_model('m.gguf', context = 'q', n_ctx = 1024L, logits_all = TRUE, n_gpu_layers = 12L)
  expect_s3_class(model, 'ps_model')

  expect_equal(ps_query(model), 'hello world')
  expect_equal(ps_query_n_times(model, 3), rep('x', 3))

  lp <- ps_query_log_probs(model)
  expect_equal(lp$tokens, c('a', 'b'))
  expect_equal(lp$probs, c(0.3, 0.7))

  one <- ps_sample_token_adjusted(
    model = model,
    top_k = 8L,
    top_p = 0.9,
    adjust_fn = function(x) x,
    use_live_state = FALSE,
    context_tokens = c(10L, 20L),
    prev_probs = c(0.2, 0.7),
    commit_token = FALSE
  )
  expect_equal(one$top_k, 8L)
  expect_equal(one$used_live_state, FALSE)
  expect_equal(one$sampled_token$token, 'a')
  expect_equal(py$sample_token_adjusted_call$commit_token, FALSE)
  expect_equal(py$sample_token_adjusted_call$context_tokens, as.list(c(10L, 20L)))
  expect_equal(py$sample_token_adjusted_call$prev_probs, as.list(c(0.2, 0.7)))

  out <- ps_generate_adjusted(
    model = model,
    top_k = 8L,
    top_p = 0.9,
    adjust_fn = function(x) x,
    max_tokens = 12L,
    alpha = 2,
    sampling_method = 'smoke',
    branch_sampler = 'metropolis'
  )
  expect_equal(out$hyperparams$top_k, 8L)
  expect_equal(out$sampling_method, 'smoke')

  ds <- ps_test_dataset_adjusted(model, c('p1', 'p2'), 8L, 0.9, function(x) x, 16L)
  expect_equal(length(ds), 2)
})


test_that('local backend setup validates path', {
  expect_error(
    ps_backend_setup_local('/definitely/not/a/real/path'),
    'must be an existing directory'
  )
})


test_that('ps_backend_setup prefers python3.13 by default when available', {
  created_python <- NULL

  testthat::local_mocked_bindings(
    .ps_default_python = function() '/usr/bin/python3.13',
    virtualenv_exists = function(envname) FALSE,
    virtualenv_create = function(envname, python) {
      created_python <<- python
      invisible(NULL)
    },
    virtualenv_install = function(envname, packages, ignore_installed) invisible(NULL),
    use_virtualenv = function(envname, required = TRUE) invisible(NULL),
    ps_reset_module = function() invisible(NULL),
    .package = 'problmsolver'
  )

  expect_no_error(ps_backend_setup(envname = 'r-problmsolver'))
  expect_equal(created_python, '/usr/bin/python3.13')
})


test_that('ps_r_adjust_fn validates input function', {
  expect_error(ps_r_adjust_fn(1), '`fn` must be a function')

  f <- ps_r_adjust_fn(function(ctx) {
    tp <- ctx$token_probs
    tp + 0.1
  })
  expect_false(is.null(f))
})
