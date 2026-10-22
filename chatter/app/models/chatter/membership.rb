module Chatter
  class Membership < ApplicationRecord
    belongs_to :conversation
    belongs_to :participant, polymorphic: true

    enum :role, { member: 0, owner: 1 }

    validates :participant_id,
      uniqueness: { scope: %i[conversation_id participant_type] }
  end
end
