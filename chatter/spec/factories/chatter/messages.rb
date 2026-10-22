FactoryBot.define do
  factory :chatter_message, class: "Chatter::Message" do
    association :conversation, factory: :chatter_conversation
    association :sender, factory: :person
    sequence(:content) { |n| "Message body #{n}" }
  end
end
