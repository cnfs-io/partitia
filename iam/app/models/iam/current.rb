module Iam
  # Per-request identity, carrying the resolved canonical principal (never an IdP
  # subject). Reset automatically between requests by ActiveSupport. Feeds
  # `current_user` and, later, `pundit_user` (ADR 0004).
  class Current < ActiveSupport::CurrentAttributes
    attribute :user
  end
end
