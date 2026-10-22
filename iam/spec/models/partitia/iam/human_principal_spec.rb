require "rails_helper"

RSpec.describe Partitia::Iam::HumanPrincipal do
  def create_root(email: "root@acme.test")
    Partitia::Iam::HumanPrincipal.create!(name: "root", email: email, root: true)
  end

  describe "root (ADR 0004)" do
    it "rejects a second root at the model layer" do
      create_root
      second = Partitia::Iam::HumanPrincipal.new(name: "root2", root: true)
      expect(second).not_to be_valid
      expect(second.errors[:root]).to be_present
    end

    it "rejects a second root at the DB layer (partial unique index)" do
      create_root
      second = Partitia::Iam::HumanPrincipal.new(name: "root2", root: true)
      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "cannot be demoted through a normal update" do
      root = create_root
      expect(root.update(root: false)).to be(false)
      expect(root.errors[:root]).to be_present
    end

    it "cannot be destroyed" do
      root = create_root
      expect { root.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "holds no access keys" do
      root = create_root
      credential = Partitia::Iam::Credential.new(owner: root)
      expect(credential).not_to be_valid
      expect(credential.errors[:owner]).to be_present
    end

    it "leaves non-root humans and machines unaffected" do
      create_root
      expect(Partitia::Iam::HumanPrincipal.create!(name: "alice")).to be_persisted
      expect(Partitia::Iam::HumanPrincipal.create!(name: "bob")).to be_persisted
      machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")
      expect(create(:partitia_iam_credential, owner: machine)).to be_persisted
    end

    it "forbids a machine from being root" do
      machine = Partitia::Iam::MachinePrincipal.new(name: "worker", root: true)
      expect(machine).not_to be_valid
      expect(machine.errors[:root]).to be_present
    end
  end

  describe "link token (ADR 0004)" do
    it "issues a one-time token, storing only its digest" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      token = principal.issue_link_token!

      expect(token).to be_present
      expect(principal.link_token_digest).to eq(Partitia::Iam::Secret.digest(token))
      expect(principal.link_token_digest).not_to eq(token)
      expect(principal.link_token_expires_at).to be > Time.current
    end

    it "finds a principal by a matching, unexpired token" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      token = principal.issue_link_token!
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token(token)).to eq(principal)
    end

    it "returns nil for a wrong token" do
      Partitia::Iam::HumanPrincipal.create!(name: "alice").issue_link_token!
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token("iam_secret_bogus")).to be_nil
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token(nil)).to be_nil
    end

    it "returns nil for an expired token" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      token = principal.issue_link_token!
      principal.update_column(:link_token_expires_at, 1.hour.ago)
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token(token)).to be_nil
    end

    it "makes a consumed token unusable" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      token = principal.issue_link_token!
      principal.consume_link_token!

      expect(principal.link_token_digest).to be_nil
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token(token)).to be_nil
    end
  end
end
