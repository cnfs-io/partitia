FactoryBot.define do
  factory :chatter_membership, class: "Chatter::Membership" do
    association :conversation, factory: :chatter_conversation
    association :participant, factory: :person
    role { :member }
  end
end
