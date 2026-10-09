# Minimal stand-in for ActionDispatch::Request satisfying the resolver contract
# (#host, #subdomain, #get_header). Resolvers never touch anything else.
class FakeRequest
  def initialize(host:, headers: {})
    @host = host
    @headers = headers
  end

  attr_reader :host

  # Mirrors ActionDispatch's default subdomain parse (everything left of the
  # registered domain's last two labels). Good enough for the resolver's
  # fallback path in specs.
  def subdomain
    labels = @host.to_s.split(".")
    labels.length > 2 ? labels[0...-2].join(".") : ""
  end

  def get_header(key)
    @headers[key]
  end
end
