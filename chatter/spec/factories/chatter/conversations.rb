FactoryBot.define do
  factory :chatter_conversation, class: "Chatter::Conversation" do
    kind { :group }
    sequence(:name) { |n| "Group #{n}" }

    trait :direct do
      kind { :direct }
      name { nil }
    end
  end
end
