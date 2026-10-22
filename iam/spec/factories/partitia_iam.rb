FactoryBot.define do
  # The tenant-plane singleton. The factory routes through .instance so it
  # respects the id=1 singleton contract rather than fighting it.
  factory :iam_account, class: "Iam::Account" do
    name { "Acme" }

    initialize_with { Iam::Account.instance(name: name) }
    to_create { |account| account }
  end

  factory :iam_human_principal, class: "Iam::HumanPrincipal" do
    sequence(:name) { |n| "user#{n}" }
  end

  factory :iam_machine_principal, class: "Iam::MachinePrincipal" do
    sequence(:name) { |n| "machine#{n}" }
  end

  factory :iam_credential, class: "Iam::Credential" do
    association :owner, factory: :iam_machine_principal
    # access_key_id / secret_digest are generated on create by the model.
  end

  factory :iam_identity_link, class: "Iam::IdentityLink" do
    association :principal, factory: :iam_human_principal
    sequence(:issuer) { |n| "https://idp#{n}.example" }
    sequence(:subject) { |n| "subject-#{n}" }
  end
end
