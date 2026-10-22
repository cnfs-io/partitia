# ⚠️  DEV/TEST SCAFFOLD — written by `rails g chatter:install:dev`.
# A non-human participant, proving chatter's polymorphic seam works across
# heterogeneous types (a Person and an Agent share no base class yet both
# participate). Safe to delete when done.
class Agent < ApplicationRecord
  include Chatter::Participant

  validates :name, presence: true

  def chatter_display_name
    name
  end
end
