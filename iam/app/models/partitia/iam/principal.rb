module Partitia
  module Iam
    # The authenticating identity (ADR 0003 Decision 1). A single STI model unifies
    # humans and machines; account-root is a role/attribute on a principal, NOT a
    # subclass. One credential path serves all principal types (Credential has a
    # polymorphic owner).
    #
    # `type` is the framework STI column and stays a real Rails column — the
    # "strings not enums" rule is about vocabulary fields (status/kind), not STI.
    class Principal < ApplicationRecord
      include Partitia::Iam::HasUrn

      has_many :credentials, class_name: "Partitia::Iam::Credential", as: :owner, dependent: :destroy

      validates :name, presence: true
    end
  end
end
