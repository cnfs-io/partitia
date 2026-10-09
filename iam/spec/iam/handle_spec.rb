require "rails_helper"

RSpec.describe Iam::Handle do
  describe ".generate" do
    it "produces a handle of the default length in the Crockford charset" do
      handle = described_class.generate
      expect(handle.length).to eq(described_class::LENGTH)
      expect(handle).to match(described_class::FORMAT)
    end

    it "excludes the ambiguous characters 0/1/i/l/o/u" do
      joined = Array.new(200) { described_class.generate }.join
      expect(joined).not_to match(/[01ilou]/)
    end

    it "is effectively unique across generations" do
      handles = Array.new(500) { described_class.generate }
      expect(handles.uniq.length).to eq(handles.length)
    end
  end

  describe ".valid?" do
    it "accepts a well-formed handle and rejects malformed input" do
      expect(described_class.valid?(described_class.generate)).to be(true)
      expect(described_class.valid?("has O and 1")).to be(false)
      expect(described_class.valid?("short")).to be(false)
    end
  end
end
