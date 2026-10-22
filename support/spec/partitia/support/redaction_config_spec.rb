# frozen_string_literal: true

RSpec.describe Partitia::Support::RedactionConfig do
  after do
    described_class.reset_instance!
    ENV.delete("PARTITIA_REDACTION_ADDITIONAL_FIELDS")
  end

  it "ships the family-wide sensitive defaults" do
    described_class.reset_instance!

    expect(described_class.sensitive_fields)
      .to include(:sub, :email, :access_key_id, :principal_id,
                  :id_token, :code_verifier, :client_secret, :hmac_key)
  end

  it "answers the predicate for a default field (string or symbol)" do
    described_class.reset_instance!

    expect(described_class.sensitive_field?("email")).to be(true)
    expect(described_class.sensitive_field?(:client_secret)).to be(true)
    expect(described_class.sensitive_field?(:bundle_id)).to be(false)
  end

  it "extends via additional_fields WITHOUT dropping the defaults (merge)" do
    ENV["PARTITIA_REDACTION_ADDITIONAL_FIELDS"] = "ssn,date_of_birth"
    described_class.reset_instance!

    expect(described_class.sensitive_fields).to include(:ssn, :date_of_birth)
    expect(described_class.sensitive_fields).to include(:email) # defaults retained
  end

  it "de-duplicates so the set is clean" do
    ENV["PARTITIA_REDACTION_ADDITIONAL_FIELDS"] = "email,email"
    described_class.reset_instance!

    expect(described_class.sensitive_fields.count(:email)).to eq(1)
  end

  # The guard shape 008 will consume: a payload leaks nothing when its keys have
  # no intersection with the sensitive set.
  it "supports the intersection guard against instrument payload keys" do
    described_class.reset_instance!

    clean = { bundle_id: 1, path: "/x" }
    leaky = { bundle_id: 1, email: "a@b.c", client_secret: "z" }

    expect(clean.keys & described_class.sensitive_fields).to eq([])
    expect(leaky.keys & described_class.sensitive_fields)
      .to contain_exactly(:email, :client_secret)
  end
end
