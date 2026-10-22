require "rails_helper"

RSpec.describe Partitia::Cognito do
  describe "configuration slots" do
    it "defaults policy_resolver to :invite_only (fail closed)" do
      expect(described_class.policy_resolver.call(nil)).to eq(:invite_only)
    end

    it "defaults session_key to :partitia_iam_user_id" do
      expect(described_class.session_key).to eq(:partitia_iam_user_id)
    end

    it "defaults the sign-in/out paths to /" do
      expect(described_class.after_sign_in_path).to eq("/")
      expect(described_class.after_sign_out_path).to eq("/")
    end

    it "raises a helpful configuration error when identity_resolver is unset" do
      expect { described_class.identity_resolver }
        .to raise_error(Partitia::Cognito::ConfigurationError, /identity_resolver is not configured/)
    end

    it "raises a helpful configuration error when provider is unset" do
      expect { described_class.provider }
        .to raise_error(Partitia::Cognito::ConfigurationError, /provider is not configured/)
    end
  end
end
