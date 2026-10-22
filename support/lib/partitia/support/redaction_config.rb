# frozen_string_literal: true

require_relative "config"

module Partitia
  module Support
    # The family-wide "what must never be logged or attached as a span attribute"
    # list — config, not constants scattered through guards and specs. A
    # Partitia::Support::Config subclass so a host can tune it through the usual chain
    # (config/partitia_redaction.yml → credentials.partitia_redaction → ENV["PARTITIA_REDACTION_*"]).
    #
    # 008's enrichment guards (and any future redaction code) read the field list
    # from here, so "what is PII" lives in one place and grows by a one-line config
    # change rather than by editing every guard.
    #
    # Extending (merge, don't replace): a gem or app appends its own sensitive
    # names without re-listing the defaults —
    #
    #   ENV["PARTITIA_REDACTION_ADDITIONAL_FIELDS"] = "ssn,date_of_birth"   # comma list
    #   # config/partitia_redaction.yml:
    #   #   additional_fields: [ssn, date_of_birth]
    #   # credentials.partitia_redaction.additional_fields: [...]
    #
    # `sensitive_fields` returns DEFAULT_FIELDS ∪ additional_fields — the defaults
    # are always retained.
    class RedactionConfig < Config
      config_name :partitia_redaction

      # Family-wide defaults. Identity subject and contact PII, IAM identifiers,
      # session identifiers, and the OIDC/secret token names already enumerated by
      # the `logging`/`telemetry` skills' redaction rules.
      DEFAULT_FIELDS = %i[
        sub subject email
        access_key_id principal_id
        session_id sid session
        id_token access_token refresh_token code code_verifier
        client_secret secret password hmac_key
      ].freeze

      # Host/gem extension point — merged onto (never replacing) DEFAULT_FIELDS.
      attr_config additional_fields: []

      class << self
        # The merged, de-duplicated set of sensitive field names (symbols, to match
        # instrument(...) payload keys). A guard can assert
        # `payload.keys & Partitia::Support::RedactionConfig.sensitive_fields == []`.
        def sensitive_fields
          (DEFAULT_FIELDS + Array(instance.additional_fields).map(&:to_sym)).uniq
        end

        # True when `name` (string or symbol) is a sensitive field.
        def sensitive_field?(name)
          sensitive_fields.include?(name.to_sym)
        end
      end
    end
  end
end
