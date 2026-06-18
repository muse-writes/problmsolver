test_that('public API exports are present', {
  exports <- getNamespaceExports('problmsolver')

  expected <- c(
    'ps_configure', 'ps_available', 'ps_python_config', 'ps_module', 'ps_reset_module',
    'ps_backend_setup', 'ps_backend_setup_local', 'ps_use_backend_env',
    'ps_metropolis_sampler', 'ps_beam_sampler', 'ps_sample_low_temp',
    'ps_sample_power_dist', 'ps_adjust_identity',
    'ps_model', 'ps_change_context', 'ps_query', 'ps_query_n_times',
    'ps_query_log_probs', 'ps_generate_adjusted', 'ps_test_dataset_adjusted',
    'ps_get_math500', 'ps_get_problems_math500'
  )

  expect_true(all(expected %in% exports))
})


test_that('backend probe is stable', {
  ok <- ps_available()
  expect_type(ok, 'logical')
  expect_length(ok, 1)
})


test_that('module import behavior is sensible with/without backend', {
  if (ps_available()) {
    expect_no_error(mod <- ps_module())
    expect_false(is.null(mod))
  } else {
    expect_error(ps_module(), 'Python module `problm_solver` is not available')
  }
})


test_that('configure does not error when required = FALSE', {
  expect_no_error(ps_configure(required = FALSE))
})
