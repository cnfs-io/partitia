require "rails_helper"

RSpec.describe Partitia::Tenanted::Resolvers do
  describe Partitia::Tenanted::Resolvers::Base do
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
      expect(described_class.default).to be_a(Partitia::Tenanted::Resolvers::Subdomain)
      expect(described_class.default.call(FakeRequest.new(host: "www.example.com"))).to be_nil
      expect(
        described_class.default.call(FakeRequest.new(host: "#{Partitia::Tenanted::RESERVED_HANDLE}.example.com"))
      ).to be_nil
      expect(described_class.default.call(FakeRequest.new(host: "acme.example.com"))).to eq("acme")
    end
  end
end
