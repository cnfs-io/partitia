require "rails_helper"

# Plan 005 WS4: diagnostic logging is behavior, so test it with a capturing
# backend (never stdout assertions). Covers tag correctness, level routing,
# redaction, block-form laziness, and the default-level silence contract.
RSpec.describe "iam diagnostic logging", :logs do
  def assertion(**overrides)
    { issuer: "https://idp.example", subject: "sub-1", email: "uma@x.test", name: "Uma" }.merge(overrides)
  end

  describe "tag correctness" do
    it "tags every line from a jit resolve with [cnfs_iam]" do
      Iam::Resolution.resolve(assertion: assertion, policy: :jit)

      expect(captured_log.messages).not_to be_empty
      expect(captured_log.messages).to all(start_with("[cnfs_iam]"))
    end

    it "tags model lines (credential, human_principal) with [cnfs_iam]" do
      credential = FactoryBot.create(:iam_credential)
      credential.owner.issue_link_token! if credential.owner.is_a?(Iam::HumanPrincipal)

      expect(captured_log.tagged("cnfs_iam")).to include(a_string_matching(/credential issued/))
    end
  end

  describe "level routing" do
    it "logs the jit first-sighting provision at info" do
      Iam::Resolution.resolve(assertion: assertion, policy: :jit)

      expect(captured_log.at(:info).join("\n")).to include("jit provision: created principal")
    end

    it "logs a resolve failure at warn, keyed by the failure vocabulary" do
      Iam::Resolution.resolve(assertion: assertion, policy: :invite_only) # unknown identity, no token

      expect(captured_log.at(:warn).join("\n")).to include("resolve failed: #{Iam::Resolution::UNKNOWN_IDENTITY}")
    end

    it "logs the resolve entry at debug" do
      Iam::Resolution.resolve(assertion: assertion, policy: :jit)

      expect(captured_log.at(:debug).join("\n")).to include("resolve: policy=jit")
    end

    it "logs a rejected credential auth at warn" do
      credential = FactoryBot.create(:iam_credential)

      Iam::Credential.authenticate(credential.access_key_id, "wrong-secret")

      expect(captured_log.at(:warn).join("\n")).to include("credential auth rejected")
    end
  end

  describe "redaction" do
    it "never logs a bootstrap/link token across issue, consume, and resolve" do
      principal = Iam::HumanPrincipal.create!(name: "invitee")
      token = principal.issue_link_token! # sentinel: a real, known token value

      Iam::Resolution.resolve(assertion: assertion, policy: :invite_only, link_token: token)

      expect(token).to be_present
      expect(captured_log.joined).not_to include(token)
    end

    it "never logs a credential secret across issue and authenticate" do
      credential = FactoryBot.create(:iam_credential)
      secret = credential.secret # sentinel: the one-time plaintext

      Iam::Credential.authenticate(credential.access_key_id, secret)

      expect(secret).to be_present
      expect(captured_log.joined).not_to include(secret)
    end

    it "never logs the IdP subject or email on the jit path" do
      Iam::Resolution.resolve(assertion: assertion, policy: :jit)

      expect(captured_log.joined).not_to include(assertion[:subject])
      expect(captured_log.joined).not_to include(assertion[:email])
    end
  end

  describe "block-form laziness" do
    it "does not evaluate a debug block when the tag level is info" do
      CnfsSupport::Logging.levels["cnfs_iam"] = :info
      logger = CnfsSupport::Logging.build_for("Iam::Resolution")

      expect { logger.debug { raise "block must not be evaluated at :info" } }.not_to raise_error
    end
  end

  describe "silence at the default floor" do
    it "at :info a jit login emits only the mutation ledger, no debug spam" do
      CnfsSupport::Logging.levels[:default] = :info

      Iam::Resolution.resolve(assertion: assertion, policy: :jit)

      expect(captured_log.at(:debug)).to be_empty
      expect(captured_log.at(:warn)).to be_empty
      # The ledger: jit provision + identity link bound.
      expect(captured_log.at(:info)).to contain_exactly(
        a_string_matching(/jit provision: created principal/),
        a_string_matching(/identity link bound/)
      )
    end
  end

  # The concern's own gem-tag handling (self is the host controller): drive it
  # through the dummy's ProbeController. iam does not infer_spec_type by
  # location, so declare the type explicitly.
  describe "Authenticatable concern tag", type: :request do
    it "tags resolve_current_user under [cnfs_iam], not the host controller" do
      get "/whoami"

      expect(captured_log.tagged("cnfs_iam").join("\n")).to include("resolve_current_user: authenticated=false")
    end

    it "logs the authz denial at warn under [cnfs_iam]" do
      get "/protected"

      expect(captured_log.at(:warn).join("\n")).to include("authz gate: denied (anonymous)")
      expect(captured_log.tagged("cnfs_iam")).to include(a_string_matching(/authz gate: denied/))
    end
  end
end
