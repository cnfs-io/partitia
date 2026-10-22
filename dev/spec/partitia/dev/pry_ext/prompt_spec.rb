RSpec.describe Partitia::Dev::PryExt::Prompt do
  describe ".color" do
    it "wraps named colors in readline-safe ANSI escapes" do
      expect(described_class.color(:blue, "x")).to eq("\001\e[34m\002x\001\e[0m\002")
    end

    it "accepts raw SGR integers and falls back to 0 for unknown names" do
      expect(described_class.color(90, "x")).to eq("\001\e[90m\002x\001\e[0m\002")
      expect(described_class.color(:mauve, "x")).to eq("\001\e[0m\002x\001\e[0m\002")
    end

    it "treats grey and gray alike" do
      expect(described_class.color(:grey, "x")).to eq(described_class.color(:gray, "x"))
    end
  end

  describe ".render_segment" do
    it "renders nothing for nil or empty text" do
      expect(described_class.render_segment({ color: :red, body: -> { nil } })).to eq("")
      expect(described_class.render_segment({ color: :red, body: -> { "" } })).to eq("")
    end

    it "brackets uncolored text" do
      expect(described_class.render_segment({ color: nil, body: -> { :acme } })).to eq("[acme]")
    end

    it "brackets colored text" do
      expect(described_class.render_segment({ color: :blue, body: -> { "acme" } }))
        .to eq("[#{described_class.color(:blue, "acme")}]")
    end
  end

  describe ".register_segment" do
    it "ignores registrations without a block" do
      described_class.register_segment(color: :red)

      expect(described_class.segment_registry).to be_empty
    end
  end

  describe ".render_segments" do
    {
      "development" => :green, "production" => :red, "test" => :yellow
    }.each do |env, color|
      it "colors the #{env} env segment #{color}, then appends contributed segments" do
        stub_const("Rails", double("Rails", env: env))
        described_class.register_segment(color: :blue) { "acme" }
        described_class.register_segment { nil }

        expect(described_class.render_segments)
          .to eq("[#{described_class.color(color, env)}][#{described_class.color(:blue, "acme")}]")
      end
    end
  end
end
