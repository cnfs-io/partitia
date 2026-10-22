# frozen_string_literal: true

RSpec.describe Partitia::Support::UrnConfig do
  after do
    described_class.reset_instance!
    ENV.delete("PARTITIA_URN_PARTITION")
  end

  it "defaults the partition to partitia" do
    described_class.reset_instance!

    expect(described_class.partition).to eq("partitia")
  end

  it "takes the app's partition from PARTITIA_URN_PARTITION" do
    ENV["PARTITIA_URN_PARTITION"] = "acme"
    described_class.reset_instance!

    expect(described_class.partition).to eq("acme")
  end
end
