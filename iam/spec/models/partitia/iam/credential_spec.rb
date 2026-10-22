require "rails_helper"

RSpec.describe Partitia::Iam::Credential do
  let(:owner) { create(:partitia_iam_machine_principal) }

  describe "generation on create" do
    it "mints a valid, parseable access_key_id and stores only a digest" do
      credential = described_class.create!(owner: owner)

      expect(Partitia::Iam::AccessKeyId.valid?(credential.access_key_id)).to be(true)
      expect(credential.secret_digest).to be_present
      expect(credential.secret_digest).not_to eq(credential.secret)
    end

    it "exposes the plaintext secret exactly once (never re-derivable)" do
      credential = described_class.create!(owner: owner)
      expect(credential.secret).to start_with("iam_secret_")

      # Never persisted; a reloaded record cannot surface it.
      expect(credential.reload.secret).to be_nil
      expect(described_class.find(credential.id).secret).to be_nil
    end

    it "enforces access_key_id uniqueness" do
      first = described_class.create!(owner: owner)
      dup = described_class.new(owner: owner, access_key_id: first.access_key_id, secret_digest: "x")
      expect(dup).not_to be_valid
    end
  end

  describe ".authenticate" do
    it "returns the owner on the happy path" do
      credential = described_class.create!(owner: owner)
      result = described_class.authenticate(credential.access_key_id, credential.secret)
      expect(result).to eq(owner)
    end

    it "returns nil for a wrong secret" do
      credential = described_class.create!(owner: owner)
      expect(described_class.authenticate(credential.access_key_id, "iam_secret_wrong")).to be_nil
    end

    it "rejects a tampered / malformed key before touching the DB" do
      credential = described_class.create!(owner: owner)
      tampered = credential.access_key_id.dup
      tampered[-1] = tampered[-1] == "q" ? "r" : "q"

      expect(described_class).not_to receive(:find_by)
      expect(described_class.authenticate(tampered, credential.secret)).to be_nil
      expect(described_class.authenticate("garbage", credential.secret)).to be_nil
    end

    it "returns nil for an unknown but well-formed key" do
      unknown = Partitia::Iam::AccessKeyId.generate(account_handle: "handle01")
      expect(described_class.authenticate(unknown, "iam_secret_x")).to be_nil
    end
  end

  describe "polymorphic owner" do
    it "works for both principal subclasses" do
      human = create(:partitia_iam_human_principal)
      machine = create(:partitia_iam_machine_principal)

      human_cred = described_class.create!(owner: human)
      machine_cred = described_class.create!(owner: machine)

      expect(described_class.authenticate(human_cred.access_key_id, human_cred.secret)).to eq(human)
      expect(described_class.authenticate(machine_cred.access_key_id, machine_cred.secret)).to eq(machine)
    end
  end

  describe "#to_urn" do
    it "uses access_key as resource_type and the access_key_id as resource_id" do
      Partitia::Iam.config.account_handle = "handle01"
      credential = described_class.create!(owner: owner)
      expect(credential.to_urn).to eq("urn:partitia:iam::handle01:access_key/#{credential.access_key_id}")
    ensure
      Partitia::Iam.config.account_handle = nil
    end
  end
end
