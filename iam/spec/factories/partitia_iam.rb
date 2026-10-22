FactoryBot.define do
  # The tenant-plane singleton. The factory routes through .instance so it
  # respects the id=1 singleton contract rather than fighting it.
  factory :partitia_iam_account, class: "Partitia::Iam::Account" do
    name { "Acme" }

    initialize_with { Partitia::Iam::Account.instance(name: name) }
    to_create { |account| account }
  end

  factory :partitia_iam_human_principal, class: "Partitia::Iam::HumanPrincipal" do
    sequence(:name) { |n| "user#{n}" }
  end

  factory :partitia_iam_machine_principal, class: "Partitia::Iam::MachinePrincipal" do
    sequence(:name) { |n| "machine#{n}" }
  end

  factory :partitia_iam_credential, class: "Partitia::Iam::Credential" do
    association :owner, factory: :partitia_iam_machine_principal
    # access_key_id / secret_digest are generated on create by the model.
  end

  factory :partitia_iam_identity_link, class: "Partitia::Iam::IdentityLink" do
    association :principal, factory: :partitia_iam_human_principal
    sequence(:issuer) { |n| "https://idp#{n}.example" }
    sequence(:subject) { |n| "subject-#{n}" }
  end
end
