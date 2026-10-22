require "rails_helper"

# Piece 5, single-tenant-testable surface. Partitia::Iam::TenantSeeder.call runs inside an
# already-selected database (Plan 001's contract) and seeds identity there — it
# needs no tenancy to exercise, so we drive it directly with a context double.
# The full multi-tenant behavior (registration into Partitia::Tenanted.after_provision,
# cross-tenant isolation, current_account_handle returning the tenant handle) is
# proven in Plan 004's integration dummy — see progress.md.
RSpec.describe Partitia::Iam::TenantSeeder do
  def context(name: "Acme", owner_email: "owner@acme.test")
    Struct.new(:name, :owner_email).new(name, owner_email)
  end

  it "seeds the Account singleton with the context name" do
    described_class.call(context(name: "Acme"))
    expect(Partitia::Iam::Account.instance.name).to eq("Acme")
  end

  it "seeds exactly one root principal from the context owner email, with a usable token" do
    described_class.call(context(owner_email: "owner@acme.test"))

    root = Partitia::Iam::HumanPrincipal.find_by(root: true)
    expect(root.email).to eq("owner@acme.test")
    expect(Partitia::Iam::HumanPrincipal.where(root: true).count).to eq(1)
    expect(Partitia::Iam::HumanPrincipal.find_by_link_token(described_class.last_bootstrap_token)).to eq(root)
  end

  it "uses one code path for the platform run (name = Platform)" do
    described_class.call(context(name: "Platform", owner_email: "ops@platform.test"))
    expect(Partitia::Iam::Account.instance.name).to eq("Platform")
    expect(Partitia::Iam::HumanPrincipal.find_by(root: true).email).to eq("ops@platform.test")
  end

  it "propagates a raise (a second seed can't create a second root)" do
    described_class.call(context)
    expect { described_class.call(context) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "is inert in single-tenant apps (not registered without partitia-tenanted)" do
    expect(defined?(Partitia::Tenanted)).to be_nil
  end
end
