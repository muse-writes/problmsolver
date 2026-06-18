# probLM Solver R Package Plan

## Objective
Create a clean R package API that uses Python `problm_solver` as a backend via `reticulate`, so R users do not need to work with Python objects directly in ad-hoc scripts.

## Scope (MVP)
1. Environment/backend controls
   - configure Python interpreter
   - check backend availability
   - inspect active Python config
2. Core model API
   - create model instances
   - query once / query n times
   - query token probabilities
   - adjusted generation
   - dataset evaluation
3. Built-in sampler constructors
   - MetropolisSampler
   - BeamSampler
   - SampleLowTemp
   - SamplePowerDist
   - adjust_identity
4. Dataset helpers
   - load MATH500 data
   - load MATH500 problems

## Design Decisions
- Keep wrappers thin and explicit.
- Return plain R lists/data frames where practical.
- Preserve access to Python callables for advanced users (e.g. `adjust_fn` arguments).
- Use namespaced `ps_*` functions to keep API discoverable.

## Follow-up (after MVP)
- Add unit tests with mocked Python layer.
- Add vignettes with end-to-end examples.
- Add optional typed wrappers for `LLMOutputData*` classes.
- Add CRAN-friendly guidance for backend setup.
