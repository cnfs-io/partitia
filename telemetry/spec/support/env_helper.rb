# Set ENV vars for the duration of a block, restoring the previous values and
# dropping every memoized config instance on both sides.
module EnvHelper
  def with_env(vars)
    saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    reset_telemetry_config!
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    reset_telemetry_config!
  end

  def reset_telemetry_config!
    Partitia::Telemetry::Config.reset_instance!
    Partitia::Support::RedactionConfig.reset_instance!
    Partitia::Telemetry.reset_prefixes!
  end
end

RSpec.configure { |config| config.include EnvHelper }
