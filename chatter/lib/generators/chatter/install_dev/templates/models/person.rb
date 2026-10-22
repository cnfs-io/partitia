# ⚠️  DEV/TEST SCAFFOLD — written by `rails g chatter:install:dev`.
# A host-side participant model so chatter has something to talk as. In a real
# host these are your existing domain models (User, etc.) that include
# Chatter::Participant — you would NOT generate this. Safe to delete when done.
class Person < ApplicationRecord
  include Chatter::Participant

  validates :name, presence: true

  def chatter_display_name
    name
  end
end
