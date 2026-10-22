module Chatter
  # The seam the host mixes into any model that can take part in conversations.
  # The engine talks to participants only through this concern and the polymorphic
  # associations it declares — it never references a host model constant directly.
  module Participant
    extend ActiveSupport::Concern

    included do
      has_many :memberships,
        as: :participant,
        class_name: "Chatter::Membership",
        dependent: :destroy

      has_many :conversations,
        through: :memberships,
        class_name: "Chatter::Conversation"

      has_many :sent_messages,
        as: :sender,
        class_name: "Chatter::Message",
        dependent: :destroy
    end

    # Name shown in the engine's views. Hosts should override this to point at
    # whatever attribute carries the participant's name. The default is safe and
    # never assumes a host attribute.
    def chatter_display_name
      "#{model_name.human} ##{id}"
    end
  end
end
