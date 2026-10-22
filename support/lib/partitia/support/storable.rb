require "active_support/concern"
require "active_support/core_ext/string/inflections"

module CnfsSupport
  # A per-model filesystem location for reading/writing a model's files.
  #
  #   module Okf
  #     class Bundle < ApplicationRecord
  #       include CnfsSupport::Storable
  #     end
  #   end
  #
  #   bundle.storage_path                  # => <root>/storage/okf/bundle/42
  #   bundle.storage_path("cache")         # => <root>/cache/okf/bundle/42
  #   Okf::Bundle.storage_path             # => <root>/storage/okf/bundle
  #   Okf::Bundle.storage_path("exports")  # => <root>/exports/okf/bundle
  #
  # WHY IN cnfs_support: every app/engine in the family includes this plugin, so
  # the base capability belongs to the foundation gem — no model has to know
  # which storage layer is in play.
  #
  # PROGRESSIVE ENHANCEMENT (tenancy): cnfs_support has zero knowledge of
  # multi-tenancy. The path is assembled through a single swappable scope hook,
  # `CnfsSupport.storage_scope`, which by default returns nil (a flat,
  # single-tenant layout). When cnfs_tenanted is present it reassigns the hook at
  # boot to return the current tenant handle, so every path is transparently
  # scoped under that handle — with no change here and no per-model include. This
  # mirrors how migrations_paths_for is owned here and replaced by cnfs_tenanted.
  #
  # LAYOUT (segments, in order):
  #   <root> / <kind> [/ <scope>] / <model_key> [/ <record_key>]
  #
  #   root        CnfsSupport.storage_root (defaults to Rails.root, else Dir.pwd)
  #   kind        the storage class, default "storage"; other examples: "cache",
  #               "exports", "tmp". The sole positional arg.
  #   scope       the tenant handle when tenanted, omitted otherwise.
  #   model_key   component tag (minus the cnfs_ prefix) + demodulized,
  #               underscored class name, e.g. "okf/bundle" — namespaced so two
  #               gems' like-named models never collide on disk.
  #   record_key  the record's #to_param (its id by default). Present only on the
  #               instance path; omitted for the class-level directory.
  #
  # The scope segment sits under <kind> (not above it) so a single tenant's data
  # across every kind is NOT contiguous by design — each kind ("storage",
  # "cache", …) is its own top-level tree, which keeps kind-wide operations
  # (clear the cache, rsync exports) trivial. Flip DIR_SCOPE_UNDER_KIND semantics
  # by overriding storage_path if a tenant-contiguous layout is ever needed.
  module Storable
    extend ActiveSupport::Concern

    # Instance path: the directory for THIS record's files. `kind` is the storage
    # class (default "storage").
    def storage_path(kind = "storage")
      self.class.storage_path(kind).join(to_param.to_s)
    end

    class_methods do
      # Class path: the directory that holds every record of this model.
      def storage_path(kind = "storage")
        CnfsSupport.storage_path(model_key: CnfsSupport.model_key(name), kind: kind)
      end
    end
  end

  class << self
    # The scope-segment hook. Default: no scope (flat layout). cnfs_tenanted
    # reassigns this at boot to `-> { ApplicationRecord.current_tenant }` so paths
    # gain a per-tenant segment. Any callable returning a String or nil works; a
    # nil/blank result means "no scope segment for this call" (e.g. code running
    # outside any tenant context still gets a valid, unscoped path).
    attr_writer :storage_scope

    def storage_scope
      @storage_scope ||= -> { nil }
    end

    # Filesystem root under which all storage kinds live. Defaults to the Rails
    # app root when Rails is booted, else the working directory (keeps the gem
    # usable pre-boot / outside Rails, per the cnfs_support charter).
    attr_writer :storage_root

    def storage_root
      @storage_root ||=
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root
        else
          Pathname.new(Dir.pwd)
        end
    end

    # The namespaced model directory key: component tag (minus "cnfs_") plus the
    # underscored demodulized class name. "Okf::Bundle" => "okf/bundle";
    # "CnfsOkf::Bundle" => "okf/bundle". Uses the same component_tag rule as
    # logging/telemetry so a model's storage dir aligns with its log tag, but
    # drops the "cnfs_" prefix for a shorter on-disk path.
    def model_key(name)
      tag = component_tag(name).delete_prefix("cnfs_")
      demodulized = name.to_s.split("::").last.underscore
      "#{tag}/#{demodulized}"
    end

    # Assemble a storage directory path (no record segment):
    #   <root>/<kind>[/<scope>]/<model_key>
    # kind defaults to "storage". A nil/blank scope-hook result is omitted.
    def storage_path(model_key:, kind: "storage")
      kind = "storage" if kind.nil? || kind.to_s.empty?
      scope = storage_scope.call
      segments = [ kind ]
      segments << scope.to_s if scope && !scope.to_s.empty?
      segments << model_key
      storage_root.join(*segments)
    end

    # Reset memoized state — used by specs to isolate examples.
    def reset_storage!
      @storage_scope = nil
      @storage_root = nil
    end
  end
end
