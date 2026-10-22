require "rails_helper"

RSpec.describe Tenant do
  def build_tenant(**overrides)
    Tenant.new({ name: "Acme", subdomain: "acme", owner_email: "owner@acme.test" }.merge(overrides))
  end

  describe "validations" do
    it "requires name, subdomain, and owner_email" do
      tenant = Tenant.new
      tenant.valid?
      expect(tenant.errors.attribute_names).to include(:name, :subdomain, :owner_email)
    end

    it "requires a unique subdomain" do
      create_tenant!(subdomain: "acme")
      expect(build_tenant(subdomain: "acme")).not_to be_valid
    end
  end

  describe "handle generation" do
    it "assigns a handle on create from the Crockford-ish alphabet" do
      tenant = build_tenant
      tenant.valid?
      charset = Regexp.escape(Tenant::HANDLE_ALPHABET.join)
      expect(tenant.handle).to match(/\A[#{charset}]{#{Tenant::HANDLE_LENGTH}}\z/)
    end

    it "never emits an ambiguous character (0/1/i/l/o/u)" do
      100.times do
        handle = build_tenant.tap(&:valid?).handle
        expect(handle).not_to match(/[01ilou]/)
      end
    end

    it "generates distinct handles across tenants" do
      a = create_tenant!(subdomain: "aaa")
      b = create_tenant!(subdomain: "bbb")
      expect(a.handle).not_to eq(b.handle)
    end

    it "rejects a duplicate handle" do
      existing = create_tenant!(subdomain: "acme")
      expect(build_tenant(subdomain: "other", handle: existing.handle)).not_to be_valid
    end

    it "never emits the reserved platform handle, retrying past it" do
      tenant = build_tenant
      # First candidate is the reserved value; the generator must reject it and
      # retry rather than assign it.
      allow(tenant).to receive(:generate_handle_candidate)
        .and_return(CnfsTenanted::RESERVED_HANDLE, "abcdefgh")
      tenant.valid?
      expect(tenant.handle).to eq("abcdefgh")
    end
  end

  describe "immutability" do
    it "rejects a handle change on a persisted record" do
      tenant = create_tenant!(subdomain: "acme")
      tenant.handle = "changed01"
      expect(tenant).not_to be_valid
      expect(tenant.errors[:handle]).to be_present
    end

    it "allows the mutable subdomain to change" do
      tenant = create_tenant!(subdomain: "acme")
      tenant.subdomain = "acme-renamed"
      expect(tenant).to be_valid
    end
  end

  describe "reserved handle" do
    it "rejects the reserved value as a handle" do
      expect(build_tenant(handle: CnfsTenanted::RESERVED_HANDLE)).not_to be_valid
    end

    it "rejects the reserved value as a subdomain" do
      expect(build_tenant(subdomain: CnfsTenanted::RESERVED_HANDLE)).not_to be_valid
    end
  end
end
