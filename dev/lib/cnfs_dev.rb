require_relative "cnfs_dev/version"
require_relative "cnfs_dev/railtie"

module CnfsDev
  # Console/Pry integration is loaded lazily by the Railtie's `console` block;
  # see lib/cnfs_dev/pry_ext.rb. The Railtie itself is only defined when
  # Rails is present (see railtie.rb), so requiring this gem outside Rails is
  # safe.
  #
  # ----------------------------------------------------------------------------
  # Public facade for consuming gems
  # ----------------------------------------------------------------------------
  #
  # cnfs_dev encapsulates Pry's verbose internals (when_started hooks,
  # TOPLEVEL_BINDING, ANSI color escapes) so other gems can contribute console
  # ergonomics declaratively. A consuming gem (which loads after cnfs_dev) does:
  #
  #   return unless defined?(CnfsDev)
  #
  #   CnfsDev.console do |c|
  #     c.shortcuts "t", Tenant          # => t, ta, tc, tf, tl
  #     c.shortcuts "a", Account         # => a, aa, ac, af, al
  #
  #     c.command(:vst) { |name = ""| ApplicationRecord.current_tenant = name }
  #
  #     c.prompt_segment(color: :blue) do
  #       t = ApplicationRecord.current_tenant rescue nil
  #       t.to_s.empty? ? nil : t        # nil / "" renders nothing
  #     end
  #
  #     c.before_reset { FileUtils.rm_rf(Rails.root.join("tmp/bundles")) }
  #     c.reset_task "okf:sync"          # appended to the reset_project! chain
  #   end
  #
  # No Pry knowledge required: no hooks, no main binding, no escape codes. The
  # block may be called by any number of gems; each call appends. Contributions
  # are collected now and applied to `main` in a single console hook at session
  # start (see CnfsDev::PryExt), so registration order == gem load order and
  # there is exactly one place that touches the console object.
  def self.console(&block)
    raise ArgumentError, "CnfsDev.console requires a block" unless block

    PryExt::Builder.collect(&block)
  end
end
