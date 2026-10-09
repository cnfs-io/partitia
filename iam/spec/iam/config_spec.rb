require "rails_helper"

# Iam::Config is a CnfsSupport::Config subclass — values resolve from
# config/iam.yml → credentials.iam → ENV["IAM_*"]. These specs assert *our*
# keys and defaults (not anyway_config itself) and prove the secret (hmac_key)
# resolves from ENV rather than a source literal.
RSpec.describe Iam::Config do
  after { described_class.reset_instance! }

  it "exposes the family defaults when nothing is set" do
    described_class.reset_instance!

    expect(described_class.partition).to eq("cnfs")
    expect(described_class.region).to eq("")
    expect(described_class.session_key).to eq(:iam_user_id)
    expect(described_class.account_handle).to be_nil
  end

  it "falls back to the dev/test HMAC key (NON-SECRET) with no override" do
    described_class.reset_instance!

    expect(described_class.hmac_key).to eq(Iam::Config::DEFAULT_HMAC_KEY)
  end

  it "resolves the HMAC key (a secret) from IAM_HMAC_KEY, never a literal" do
    ENV["IAM_HMAC_KEY"] = "prod-key-from-env"
    described_class.reset_instance!

    expect(described_class.hmac_key).to eq("prod-key-from-env")
  ensure
    ENV.delete("IAM_HMAC_KEY")
  end

  it "overrides a non-secret default from ENV (IAM_PARTITION)" do
    ENV["IAM_PARTITION"] = "acme"
    described_class.reset_instance!

    expect(described_class.partition).to eq("acme")
  ensure
    ENV.delete("IAM_PARTITION")
  end

  # The gem and its specs read/write through Iam.config; keep that API intact.
  it "backs the Iam.config read/write API with the singleton" do
    expect(Iam.config).to be(described_class.instance)

    Iam.config.account_handle = "pinned01"
    expect(Iam.config.account_handle).to eq("pinned01")
  end
end
