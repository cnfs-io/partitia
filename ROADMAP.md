# Roadmap

## CI

- [ ] Add an RSpec job to `.github/workflows/ci.yml` alongside lint, using the same per-gem matrix (chatter, cognito, dev, iam, support, telemetry, tenanted). CI currently runs RuboCop only — the per-gem workflows carried over from the original repos never ran specs.
