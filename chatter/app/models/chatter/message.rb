module Chatter
  class Message < ApplicationRecord
    belongs_to :conversation
    belongs_to :sender, polymorphic: true

    validates :content, presence: true

    default_scope { order(:created_at) }

    # Real-time delivery: every saved message is appended to the conversation's
    # stream for all subscribers. The partial is kept at chatter/messages/message
    # so a later ActionText upgrade is localized to that partial + the form.
    broadcasts_to ->(message) { message.conversation },
      inserts_by: :append,
      target: ->(message) { "conversation_#{message.conversation_id}_messages" }
  end
end
