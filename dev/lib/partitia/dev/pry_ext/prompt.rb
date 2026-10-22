module CnfsDev
  module PryExt
    # Builds the console prompt: a Rails-env segment (green=development,
    # red=production, yellow=other) plus any segments other gems contribute via
    # CnfsDev.console { |c| c.prompt_segment(color:) { ... } }. Renders e.g.:
    #
    #   [development][acme] cnfs(main)>
    #
    # cnfs_dev is domain-agnostic: it knows nothing about tenancy or any other
    # concern. A contributing gem supplies a block returning the segment text
    # (nil or "" renders nothing) and an optional named color; this module
    # handles the ANSI escapes and Readline width markers so callers never see
    # them.
    module Prompt
      module_function

      # Named colors -> ANSI SGR codes. Callers use the names; see
      # CnfsDev::Builder#prompt_segment.
      COLORS = {
        red: 31, green: 32, yellow: 33, blue: 34,
        magenta: 35, cyan: 36, grey: 90, gray: 90
      }.freeze

      # ANSI color helper. The \001..\002 markers tell Readline these bytes are
      # non-printing so line-editing measures the prompt width correctly.
      # `code` may be a named color (Symbol) or a raw SGR integer.
      def color(code, text)
        code = COLORS.fetch(code, 0) if code.is_a?(Symbol)
        "\001\e[#{code}m\002#{text}\001\e[0m\002"
      end

      # Registry of contributed segments: { color:, body: }. Each body returns
      # the text to display (nil / "" => nothing), appended after the built-in
      # env segment in registration order.
      def segment_registry
        @segment_registry ||= []
      end

      # Append a prompt segment. `color:` is a name from COLORS (or nil for no
      # color); the block returns the segment text at render time.
      def register_segment(color: nil, &body)
        segment_registry << { color: color, body: body } if body
      end

      # Render one contributed segment to a bracketed, colorized string, or ""
      # when the body yields nothing.
      def render_segment(segment)
        text = segment[:body].call
        return "" if text.nil? || text.to_s.empty?

        colored = segment[:color] ? color(segment[:color], text) : text
        "[#{colored}]"
      end

      # The full rendered prompt prefix: built-in env segment followed by every
      # contributed segment.
      def render_segments
        env  = Rails.env.to_s
        code = { "development" => :green, "production" => :red }.fetch(env, :yellow)
        env_segment = "[#{color(code, env)}]"

        env_segment + segment_registry.map { |s| render_segment(s) }.join
      end

      def build(obj, nest_level, sep)
        name    = Pry.config.prompt_name || "pry"
        nesting = nest_level.zero? ? "" : ":#{nest_level}"
        "#{render_segments} #{name}(#{Pry.view_clip(obj)})#{nesting}#{sep} "
      end

      # Install this prompt as the active Pry prompt.
      def install!
        Pry.config.prompt = Pry::Prompt.new(
          "cnfs_rails_env",
          "Rails.env, plus any segments contributed by other gems",
          [
            proc { |obj, nest, _| build(obj, nest, ">") },
            proc { |obj, nest, _| build(obj, nest, "*") }
          ]
        )
      end
    end
  end
end
