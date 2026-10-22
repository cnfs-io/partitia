# iam configuration (identity authority).
#
# iam reads its settings through Iam::Config (a CnfsSupport::Config subclass),
# which resolves every value from config/iam.yml → credentials.iam → ENV["IAM_*"]
# with one precedence. Every setting has a working default — iam boots without
# this file in dev/test. It exists to document the production-critical HMAC key
# and the host-tunable knobs.

# HMAC-SHA256 key for machine-credential secret digests (access keys).
#
# REQUIRED in production; SECRET. The gem falls back to a fixed, NON-SECRET
# development key so dev/test round-trip without configuration — never ship that
# fallback. Because Iam::Config resolves it through the chain, you do NOT set it
# here — source the real key from Rails credentials (never inline a literal):
#
#   bin/rails credentials:edit
#     iam:
#       hmac_key: <value>
#
# or supply IAM_HMAC_KEY in the environment.

# Non-secret tunables. These live in config/iam.yml or IAM_* env vars; the block
# below is an equivalent code-level override — uncomment a line to pin a value.
#
# Iam.configure do |c|
#   # URN partition — the first segment of every URN
#   # (urn:<partition>:iam::<account>:<resource_type>/<resource_id>).
#   # Host-configurable; defaults to "cnfs". Region stays empty for IAM,
#   # mirroring AWS's global IAM service.
#   c.partition = "cnfs"
#
#   # Single-tenant account handle. Left nil, iam mints a real handle once and
#   # memoises it (ADR 0002 §2 — a real handle, never a sentinel). Pin it for a
#   # stable, human-meaningful handle baked into access-key IDs and URNs across
#   # boots. Ignored under multi-tenancy, where the active tenant's routing
#   # handle IS the account handle.
#   c.account_handle = "single"
#
#   # Session key holding the canonical principal id after authentication. Must
#   # match CnfsCognito.session_key when the broker is in use (both default to
#   # :iam_user_id, so leave this alone unless you change both).
#   c.session_key = :iam_user_id
# end
