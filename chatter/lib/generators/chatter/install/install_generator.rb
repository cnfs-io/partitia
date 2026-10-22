require "rails/generators"

module Chatter
  module Generators
    # `rails g chatter:install` — the deterministic wiring a host app runs once to
    # adopt chatter. For this milestone it does the one mechanical thing a host
    # cannot skip: mount the engine into the host's routes. Mirrors the cnfs_ui
    # install-generator idiom (Rails' own `route` helper + `say_status`).
    #
    # Deliberately standalone: chatter does NOT depend on cnfs_ui, so this writes
    # no chrome/layout/Tailwind wiring. If chatter later composes cnfs_ui, that is
    # a separate decision and a separate generator step — not smuggled in here.
    #
    # The host must still satisfy chatter's two config seams itself (they are not
    # mechanical enough to generate): set `Chatter.parent_controller` to a base
    # controller providing `current_participant`, and supply
    # `Chatter.participant_candidates`. See the engine README.
    class InstallGenerator < Rails::Generators::Base
      MOUNT_PATH = "/chatter".freeze

      desc "Mount Chatter::Engine into the host application's routes."

      def mount_engine
        # Rails' `route` helper is idempotent for an identical line — re-running
        # will not duplicate the mount.
        route %(mount Chatter::Engine => "#{MOUNT_PATH}")
        say_status :mount, %(Chatter::Engine => "#{MOUNT_PATH}"), :green
      end
    end
  end
end
