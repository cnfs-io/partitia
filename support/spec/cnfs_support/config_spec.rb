# frozen_string_literal: true

RSpec.describe CnfsSupport::Config do
  # A representative subclass, as a CNFS gem would define it.
  let(:config_class) do
    Class.new(described_class) do
      config_name :widget
      attr_config :issuer, session_ttl: 3600
      coerce_types session_ttl: :integer
    end
  end

  after do
    ENV.delete("WIDGET_ISSUER")
    ENV.delete("WIDGET_SESSION_TTL")
  end

  it "exposes defaults through the singleton delegation" do
    expect(config_class.session_ttl).to eq(3600)
  end

  it "resolves ENV vars prefixed by the config name, with coercion" do
    ENV["WIDGET_ISSUER"] = "https://idp.example.com"
    ENV["WIDGET_SESSION_TTL"] = "7200"

    expect(config_class.issuer).to eq("https://idp.example.com")
    expect(config_class.session_ttl).to eq(7200)
  end

  it "memoizes one instance per subclass, resettable for specs" do
    first = config_class.instance
    expect(config_class.instance).to be(first)

    config_class.reset_instance!
    expect(config_class.instance).not_to be(first)
  end

  it "memoizes independently across subclasses" do
    other_class = Class.new(described_class) { config_name :gadget }

    expect(config_class.instance).not_to be(other_class.instance)
  end

  it "works pre-boot without Rails loaded" do
    # The suite itself runs Rails-free; this documents the charter requirement.
    expect(defined?(Rails)).to be_nil
    expect(config_class.instance).to be_a(described_class)
  end
end
