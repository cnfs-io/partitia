class Person < ApplicationRecord
  include Chatter::Participant

  validates :name, presence: true

  def chatter_display_name
    name
  end
end
