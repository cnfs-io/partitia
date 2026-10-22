# The engine's Chatter::ApplicationController inherits from this, so it picks up
# the host's `current_participant` automatically — the engine's NotImplementedError
# default is never reached. This is the exact contract a real host (e.g. LGAT admin)
# satisfies: point Chatter at your base controller that already knows the current user.
Chatter.parent_controller = "::ApplicationController"

# Render the engine's screens inside the host's chrome (which carries the
# participant switcher). The engine keeps its own layout as a standalone default;
# the host opts it into the host layout here.
Rails.application.config.to_prepare do
  Chatter::ApplicationController.layout "application"
end

# The host knows its participant models; the engine does not. Expose every Person
# and Agent as a candidate to start conversations with.
Chatter.participant_candidates = -> { Person.all.to_a + Agent.all.to_a }
