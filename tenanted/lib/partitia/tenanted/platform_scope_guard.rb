module CnfsTenanted
  # Enforces the ADR 0003 §2 scope rule for `with_platform`: inside the reserved
  # database, the only tenanted tables that may be touched are the identity
  # tables (allowlisted by prefix, default iam_) plus Active Record's own
  # internals. Any other table access raises PlatformScopeViolation.
  #
  # Mechanism (per Plan 001 WS5.3): a `sql.active_record` subscriber scoped to
  # the block, parsing the table name out of each query. This is a behavioral
  # TRIPWIRE, not a transactional gate — sql.active_record fires after the query
  # executes, so a violating write reaches the reserved DB before the guard
  # raises. That is acceptable pre-v1: no app-model writes should ever happen in
  # the platform context, and the guard turns a mistaken one into a loud, fast
  # failure in development and test.
  module PlatformScopeGuard
    # Always allowed: Active Record's bookkeeping tables.
    AR_INTERNALS = %w[schema_migrations ar_internal_metadata].freeze

    module_function

    # Run `block` with the guard active. `prefixes` is the allowlist of table
    # name prefixes (e.g. %w[iam_]).
    def enforce(prefixes, &block)
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
        check!(event.payload, prefixes)
      end

      block.call
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    def check!(payload, prefixes)
      return if payload[:name] == "SCHEMA"
      return if payload[:cached]

      table = table_name(payload[:sql])
      return if allowed?(table, prefixes)

      raise PlatformScopeViolation,
            "with_platform: query touched non-allowlisted table #{table.inspect} " \
            "(allowed prefixes: #{prefixes.join(', ')})"
    end

    def allowed?(table, prefixes)
      return true if table.nil?
      return true if AR_INTERNALS.include?(table)

      prefixes.any? { |prefix| table.start_with?(prefix) }
    end

    # Best-effort table extraction from a SQL string, covering the DML the guard
    # cares about (INSERT INTO / UPDATE / DELETE FROM / SELECT … FROM / JOIN).
    # Transaction control and other tableless statements yield nil (allowed).
    def table_name(sql)
      match = sql.to_s.match(/(?:\binto\b|\bupdate\b|\bfrom\b|\bjoin\b)\s+["'`]?([a-zA-Z0-9_]+)["'`]?/i)
      match && match[1].downcase
    end
  end
end
