require "rails_helper"

# §3: iam emits standardized notifications for its identity/auth hot paths.
# Asserted at the notification layer (no OTel SDK) — exactly what partitia-telemetry
# turns into spans. Also proves the §0 auto-wire: Partitia::Iam models get `instrument`
# with no explicit include on Partitia::Iam::ApplicationRecord.
RSpec.describe "iam instrumentation" do
  def payloads_for(name)
    out = []
    callback = ->(_name, _start, _finish, _id, payload) { out << payload }
    ActiveSupport::Notifications.subscribed(callback, name) { yield }
    out
  end

  def assertion(**overrides)
    { issuer: "https://idp.example", subject: "sub-1", email: "uma@x.test", name: "Uma" }.merge(overrides)
  end

  describe "Partitia::Iam::Resolution.resolve" do
    it "records policy and outcome=success, nesting a provision_jit span on first sighting" do
      resolve = payloads_for("partitia_iam.resolution.resolve") do
        provision = payloads_for("partitia_iam.resolution.provision_jit") do
          described_class = Partitia::Iam::Resolution
          described_class.resolve(assertion: assertion, policy: :jit)
        end
        expect(provision.size).to eq(1)
      end

      expect(resolve.size).to eq(1)
      expect(resolve.first).to include(policy: "jit", outcome: "success")
    end

    it "records the failure vocabulary as the outcome" do
      resolve = payloads_for("partitia_iam.resolution.resolve") do
        Partitia::Iam::Resolution.resolve(assertion: assertion, policy: :invite_only)
      end

      expect(resolve.first).to include(outcome: Partitia::Iam::Resolution::UNKNOWN_IDENTITY)
    end
  end

  describe "Partitia::Iam::Credential.authenticate" do
    it "records outcome=authenticated and emits an issue span on create" do
      issued = payloads_for("partitia_iam.credential.issue") do
        @credential = FactoryBot.create(:partitia_iam_credential)
      end
      expect(issued.size).to eq(1)
      # Bounded owner_type dimension — split issuance by principal kind (WS1.2).
      expect(%w[HumanPrincipal MachinePrincipal]).to include(issued.first[:owner_type])

      secret = @credential.secret
      auth = payloads_for("partitia_iam.credential.authenticate") do
        Partitia::Iam::Credential.authenticate(@credential.access_key_id, secret)
      end
      expect(auth.first).to include(outcome: "authenticated")
    end

    it "records outcome=malformed for a bad key id (no DB/HMAC work)" do
      auth = payloads_for("partitia_iam.credential.authenticate") do
        Partitia::Iam::Credential.authenticate("not-a-key", "x")
      end
      expect(auth.first).to include(outcome: "malformed")
    end
  end

  describe "Partitia::Iam::HumanPrincipal tokens" do
    it "emits issue_link_token and consume_link_token spans" do
      principal = FactoryBot.create(:partitia_iam_human_principal)

      issued = payloads_for("partitia_iam.human_principal.issue_link_token") do
        principal.issue_link_token!
      end
      expect(issued.first).to include(root: false)

      consumed = payloads_for("partitia_iam.human_principal.consume_link_token") do
        principal.consume_link_token!
      end
      expect(consumed.size).to eq(1)
    end
  end

  describe "Partitia::Iam::RootRecovery.reset!" do
    it "emits partitia_iam.root_recovery.reset" do
      FactoryBot.create(:partitia_iam_human_principal, root: true)

      events = payloads_for("partitia_iam.root_recovery.reset") { Partitia::Iam::RootRecovery.reset! }
      expect(events.size).to eq(1)
    end
  end

  # The cardinality/PII guard (WS1.5): no iam span may carry a sensitive/
  # high-cardinality attribute. The forbidden set is READ FROM the redaction
  # config (Plan 006), not hard-coded here — a new sensitive field added to the
  # config is enforced across every span automatically.
  describe "cardinality/PII guard" do
    def all_span_payloads
      captured = []
      callback = ->(name, _start, _finish, _id, payload) { captured << [ name, payload ] }
      ActiveSupport::Notifications.subscribed(callback, /\Apartitia_iam\./) { yield }
      captured
    end

    it "attaches no sensitive field to any iam span (list read from RedactionConfig)" do
      sensitive = Partitia::Support::RedactionConfig.sensitive_fields

      principal = FactoryBot.create(:partitia_iam_human_principal)
      credential = FactoryBot.create(:partitia_iam_credential)

      payloads = all_span_payloads do
        Partitia::Iam::Resolution.resolve(assertion: assertion, policy: :jit)
        Partitia::Iam::Credential.authenticate(credential.access_key_id, credential.secret)
        principal.issue_link_token!
      end

      payloads.each do |name, payload|
        leaked = payload.keys.map(&:to_sym) & sensitive
        expect(leaked).to be_empty, "#{name} leaked sensitive attribute(s): #{leaked.inspect}"
      end
    end
  end
end
