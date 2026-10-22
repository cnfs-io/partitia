require "rails/generators"
require "rails/generators/active_record"

module Chatter
  module Generators
    # `rails g chatter:install:dev` — scaffolds the full HOST-SIDE contract chatter
    # needs, into a throwaway development target (e.g. the `dust` scratch app), so
    # you can exercise real-time chat across browser tabs without hand-wiring it.
    #
    # ⚠️  THIS WRITES FAKE AUTH. The generated SessionController lets anyone
    # "become" any participant with no password. It is a development convenience
    # ONLY. The generator refuses to run outside RAILS_ENV=development, and every
    # file it writes carries a DEV-ONLY banner. NEVER run this against a real app.
    #
    # It is the disposable-target counterpart to `chatter:install` (mount-only):
    # where a real host writes its own participant models + `current_participant`,
    # a scratch app that gets swept away wants that setup regenerable in one
    # command. Setup-as-code for a throwaway target.
    #
    # What it writes: Person + Agent participant models (+ migrations), a fake-auth
    # SessionController + route, `current_participant` on the host's
    # ApplicationController, the switcher partial wired into the host layout, a
    # landing page (so you can pick an identity before entering /chatter), the
    # Chatter host-contract initializer, and seeds. It also mounts the engine (so
    # you don't need to run `chatter:install` separately).
    #
    # PREREQUISITE: the host must already have Tailwind set up (a Rails app created
    # with `--css=tailwind`, giving an `app/assets/tailwind/application.css`
    # entrypoint and a build). This generator does NOT bootstrap Tailwind — it
    # assumes the host has it, and warns if it doesn't. Regenerate dust WITH
    # Tailwind, then run this.
    class InstallDevGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "DEV ONLY: scaffold Person/Agent + fake-auth switcher into a throwaway host so chatter works end-to-end."

      def refuse_outside_development
        return if Rails.env.development?

        say_status :abort,
                   "chatter:install:dev is development-only (RAILS_ENV=#{Rails.env}). Refusing to run.",
                   :red
        raise Thor::Error, "chatter:install:dev refused: not in development"
      end

      def warn_loudly
        say ""
        say "  ⚠️  chatter:install:dev writes FAKE AUTH (no passwords) for local testing only.", :yellow
        say "     Never run this against a real application.", :yellow
        say ""
      end

      # This generator assumes the host already has Tailwind (see class comment).
      # Warn if the entrypoint is absent — the switcher/layout use Tailwind classes
      # and the host layout links a built stylesheet; without Tailwind you'll hit a
      # missing-asset error at render. We warn rather than abort so a host with a
      # differently-named setup can still proceed.
      def check_tailwind_present
        entrypoint = "app/assets/tailwind/application.css"
        return if File.exist?(File.join(destination_root, entrypoint))

        say_status :warn,
                   "#{entrypoint} not found — this generator assumes the host has Tailwind " \
                   "(create the app with `--css=tailwind`). Continuing, but styling/assets may fail.",
                   :yellow
      end

      def mount_engine
        route %(mount Chatter::Engine => "/chatter")
      end

      # copy_file (not template): these files contain no generator-time ERB. Using
      # `template` would ERB-process them in the GENERATOR's context — which is what
      # broke the switcher (its <%= current_participant %> is app-level ERB meant to
      # run at request time, not generation time). copy_file copies verbatim.
      def create_participant_models
        copy_file "models/person.rb", "app/models/person.rb"
        copy_file "models/agent.rb", "app/models/agent.rb"
      end

      def create_participant_migrations
        migration_template "migrations/create_people.rb.tt",
                           "db/migrate/create_people.rb"
        migration_template "migrations/create_agents.rb.tt",
                           "db/migrate/create_agents.rb"
      end

      # NOTE: we do NOT copy chatter's engine migrations here. CnfsSupport's
      # :set_migrations_paths initializer walks CnfsSupport.plugins and adds each
      # engine's db/migrate to the host's migration paths automatically, so
      # chatter_conversations/memberships/messages are already visible in place.
      # Running `chatter:install:migrations` would COPY them into the host and
      # collide with the auto-surfaced originals (duplicate table migrations).
      # Only dust's OWN models (Person/Agent, above) need migrations written here.

      def create_session_controller
        copy_file "controllers/session_controller.rb", "app/controllers/session_controller.rb"
      end

      # copy_file: the switcher's ERB (`current_participant`, `button_to`, …) is
      # APP-level, evaluated at request time in the running app — NOT generator
      # variables. Templating it would try to eval them now and fail.
      def create_switcher_partial
        copy_file "views/_switcher.html.erb", "app/views/layouts/_switcher.html.erb"
      end

      # Render the switcher at the top of the host's <body>, if a standard layout
      # is present. Idempotent via the render marker.
      def wire_switcher_into_layout
        layout = "app/views/layouts/application.html.erb"
        unless File.exist?(File.join(destination_root, layout))
          say_status :skip, "#{layout} not found — add `<%= render \"layouts/switcher\" %>` to your layout manually", :yellow
          return
        end

        marker = %(render "layouts/switcher")
        if File.read(File.join(destination_root, layout)).include?(marker)
          say_status :unchanged, "switcher already in #{layout}", :blue
          return
        end

        inject_into_file layout, %(    <%= render "layouts/switcher" %>\n), after: /<body[^>]*>\n/
      end

      def inject_current_participant
        controller = "app/controllers/application_controller.rb"
        unless File.exist?(File.join(destination_root, controller))
          say_status :skip, "#{controller} not found — define current_participant manually", :yellow
          return
        end

        if File.read(File.join(destination_root, controller)).include?("current_participant")
          say_status :unchanged, "current_participant already in #{controller}", :blue
          return
        end

        inject_into_class controller, "ApplicationController", <<~RUBY.indent(2)
          # ⚠️  DEV/TEST SCAFFOLD (chatter:install:dev). Fake auth: resolves the
          # acting participant from a session GlobalID. A real host resolves this
          # from its actual auth system. Never ship this.
          def current_participant
            gid = session[:current_participant_gid]
            GlobalID::Locator.locate(gid) if gid
          end
          helper_method :current_participant
        RUBY
      end

      def create_initializer
        copy_file "initializers/chatter_dev.rb", "config/initializers/chatter_dev.rb"
      end

      # A landing page in the host layout so you can pick an identity BEFORE
      # entering /chatter (which 403s until current_participant is set). This is
      # the fix for the chicken-and-egg where the switcher lives in the layout but
      # chatter won't render the layout without a participant.
      def create_home_page
        copy_file "controllers/home_controller.rb", "app/controllers/home_controller.rb"
        copy_file "views/home_index.html.erb", "app/views/home/index.html.erb"
      end

      def add_session_route
        route %(post "session", to: "session#update", as: :session)
      end

      # Land on the host home page (with the switcher), not straight into /chatter.
      # `route root:` is idempotent-ish; guard so a re-run doesn't stack roots.
      def set_root_route
        routes = "config/routes.rb"
        if File.read(File.join(destination_root, routes)).match?(/^\s*root\s/)
          say_status :skip, "root route already set in #{routes}", :blue
          return
        end
        route %(root "home#index")
      end

      def append_seeds
        seeds = "db/seeds.rb"
        marker = "chatter:install:dev"
        if File.exist?(File.join(destination_root, seeds)) &&
           File.read(File.join(destination_root, seeds)).include?(marker)
          say_status :unchanged, "seeds already appended to #{seeds}", :blue
          return
        end

        append_to_file seeds, "\n#{File.read(File.join(self.class.source_root, "seeds.rb"))}"
      end

      def next_steps
        say ""
        say "  ✅  chatter:install:dev done. Next:", :green
        say "        bin/rails db:migrate db:seed"
        say "        bin/dev   (or bin/rails s)"
        say "     then open / , pick an identity from the switcher, and enter the chats.", :green
        say "     Open a second tab as a different person to see real-time delivery.", :green
        say ""
      end
    end
  end
end
