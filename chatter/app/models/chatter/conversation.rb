module Chatter
  class Conversation < ApplicationRecord
    # scopes: false avoids generating a `group` class scope, which would clash
    # with ActiveRecord's `group` query method. The `direct?`/`group?` predicates
    # and `kind:` assignment still work.
    enum :kind, { direct: 0, group: 1 }, scopes: false

    has_many :memberships, dependent: :destroy
    has_many :messages, dependent: :destroy

    validates :name, presence: true, if: :group?
    validate :direct_has_exactly_two_members, if: :direct?

    # Find an existing direct conversation between the two participants, or create
    # one. This is the DM entry point; blocking/privacy rules would later hook here.
    def self.find_or_create_direct(participant_a, participant_b)
      existing = direct_between(participant_a, participant_b)
      return existing if existing

      conversation = new(kind: :direct)
      conversation.memberships.build(participant: participant_a)
      conversation.memberships.build(participant: participant_b)
      conversation.save!
      conversation
    end

    # Returns the direct conversation whose two memberships are exactly this pair,
    # or nil. Works across heterogeneous participant types.
    def self.direct_between(participant_a, participant_b)
      a_ids = Membership.where(participant: participant_a).select(:conversation_id)
      b_ids = Membership.where(participant: participant_b).select(:conversation_id)

      where(kind: :direct)
        .where(id: a_ids)
        .where(id: b_ids)
        .find { |conversation| conversation.memberships.size == 2 }
    end

    def participants
      memberships.map(&:participant)
    end

    # For a DM, the participant on the other side of the conversation from viewer.
    def other_participant(viewer)
      participants.find { |p| p != viewer }
    end

    # A human label for the conversation from a given viewer's perspective.
    def display_title(viewer)
      return name if group?

      other = other_participant(viewer)
      other ? other.chatter_display_name : "Direct message"
    end

    private

    def direct_has_exactly_two_members
      return if memberships.size == 2

      errors.add(:base, "a direct conversation must have exactly two participants")
    end
  end
end
