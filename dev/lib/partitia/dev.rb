require_relative "cnfs_dev/version"
require_relative "cnfs_dev/builder"
require_relative "cnfs_dev/railtie" if defined?(Rails::Railtie)
require "pry-byebug"

module CnfsDev
  # cnfs_dev encapsulates Pry's verbose internals (when_started hooks,
  # TOPLEVEL_BINDING, ANSI color escapes) so other gems can contribute console
  # ergonomics declaratively. A consuming gem (which loads after cnfs_dev) does,
  # in its entry file at load time:
  #
  #   return unless defined?(CnfsDev)
  #
  #   CnfsDev.console do |c|
  #     c.namespace CnfsOkf, "o"         # CnfsOkf::Bundle => ob, oba, obc, obf, obl, obp
  #     c.namespace Chorus,  "c"         # Chorus::Account => ca, ...
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
  # Builder DSL yielded by `console` lives in lib/cnfs_dev/builder.rb.
  #
  # ----------------------------------------------------------------------------
  # Registries
  # ----------------------------------------------------------------------------
  #
  # These are plain, dependency-free module-level stores — the same shape as
  # CnfsSupport.plugins. They exist the moment this file is required, so a
  # consuming gem can register at *load* time, which is earlier than the
  # Railtie's `console` block that loads the (Pry-dependent) wiring. Nothing
  # here touches Pry, Rails, or ActiveRecord, so populating them is safe in any
  # process. The heavier machinery in lib/cnfs_dev/pry_ext.rb reads these later,
  # only when a console session starts.
  def self.namespaces     = (@namespaces     ||= [])
  def self.models         = (@models         ||= [])
  def self.commands       = (@commands       ||= [])
  def self.prompt_segments = (@prompt_segments ||= [])
  def self.before_resets  = (@before_resets  ||= [])
  def self.reset_tasks    = (@reset_tasks    ||= [])

  # ----------------------------------------------------------------------------
  # Public facade for consuming gems
  # ----------------------------------------------------------------------------
  #
  # Yields a Builder (see lib/cnfs_dev/builder.rb) that appends into the
  # registries above. The block may be called by any number of gems; each call
  # appends, so registration order == gem load order. Contributions are applied
  # to the console `main` in a single hook at session start (see
  # CnfsDev::PryExt), the one place that touches the console object.
  def self.console
    raise ArgumentError, "CnfsDev.console requires a block" unless block_given?

    yield Builder.new
    nil
  end
end
