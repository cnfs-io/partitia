require "rails_helper"

RSpec.describe CnfsTenanted::Resolvers do
  describe CnfsTenanted::Resolvers::Base do
    it "normalizes blank values to nil" do
      expect(subject.present_or_nil("")).to be_nil
      expect(subject.present_or_nil(nil)).to be_nil
      expect(subject.present_or_nil("acme")).to eq("acme")
    end

    it "raises NotImplementedError for the abstract #call" do
      expect { subject.call(FakeRequest.new(host: "example.com")) }
        .to raise_error(NotImplementedError)
    end
  end

  describe ".default" do
    it "is a subdomain resolver excluding www and the reserved platform handle" do
      expect(described_class.default).to be_a(CnfsTenanted::Resolvers::Subdomain)
      expect(described_class.default.call(FakeRequest.new(host: "www.example.com"))).to be_nil
      expect(
        described_class.default.call(FakeRequest.new(host: "#{CnfsTenanted::RESERVED_HANDLE}.example.com"))
      ).to be_nil
      expect(described_class.default.call(FakeRequest.new(host: "acme.example.com"))).to eq("acme")
    end
  end
end
