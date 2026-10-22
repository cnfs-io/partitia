# Engine-shipped Stimulus controllers. Pinned under "controllers/chatter" so the
# host's existing `eagerLoadControllersFrom("controllers")` discovers them with
# identifiers like "chatter--messages". No npm/node — importmap only.
pin_all_from Chatter::Engine.root.join("app/javascript/controllers/chatter"),
  under: "controllers/chatter"
