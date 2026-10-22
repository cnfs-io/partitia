require "rails_helper"
require "rails/generators"
require "generators/partitia/cognito/install/install_generator"
require "tmpdir"
require "yaml"

RSpec.describe Partitia::Cognito::Generators::InstallGenerator do
  # A shell that fails the example instead of prompting (§5: asks nothing).
  let(:shell_class) do
    Class.new(Thor::Shell::Basic) do
      %i[ask yes? no? file_collision].each do |m|
        define_method(m) { |*args| raise "generator prompted: #{m} #{args.first}" }
      end
    end
  end

  let(:filter_logging) do
    <<~RUBY
      # Be sure to restart your server when you modify this file.
      Rails.application.config.filter_parameters += [
        :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
      ]
    RUBY
  end

  around do |example|
    Dir.mktmpdir("cognito-install") do |dir|
      @root = dir
      FileUtils.mkdir_p(File.join(dir, "config/initializers"))
      File.write(File.join(dir, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      example.run
    end
  end

  def write(path, content) = File.write(File.join(@root, path), content)
  def read(path) = File.read(File.join(@root, path))
  def exist?(path) = File.exist?(File.join(@root, path))

  def run_generator(args = [])
    out = StringIO.new
    original = $stdout
    $stdout = out
    described_class.start(args, destination_root: @root, shell: shell_class.new)
    out.string
  ensure
    $stdout = original
  end

  def snapshot
    Dir.glob("**/*", base: @root).sort.to_h { |f| [ f, File.file?(File.join(@root, f)) ? read(f) : :dir ] }
  end

  context "on a fresh app" do
    before { write("config/initializers/filter_parameter_logging.rb", filter_logging) }

    it "mounts the engine, writes the initializer and the yml, and filters code/state" do
      run_generator

      expect(read("config/routes.rb")).to include('mount Partitia::Cognito::Engine => "/auth"')
      expect(read("config/initializers/partitia_cognito.rb")).to include("Partitia::Cognito::Config.issuer")
      expect(read("config/initializers/filter_parameter_logging.rb"))
        .to include("filter_parameters += [\n  :code, :state,\n  :passw")
    end

    it "writes a yml for development (pcm's Authentik), test and production, with no secret" do
      run_generator
      yml = YAML.safe_load(read("config/partitia_cognito.yml"))

      expect(yml.keys).to contain_exactly("development", "test", "production")
      expect(yml["development"]).to eq(
        "issuer" => "http://localhost:9000/application/o/dummy/",
        "client_id" => "dummy",
        "scopes" => %w[openid email profile]
      )
      expect(yml["test"]).to include("issuer" => "http://authentik.test/application/o/dummy/",
                                     "client_id" => "test-client-id")
      expect(yml.values.flat_map(&:keys)).not_to include("client_secret")
    end

    it "takes the Authentik slug from --app-slug" do
      run_generator([ "--app-slug", "my-app" ])

      expect(YAML.safe_load(read("config/partitia_cognito.yml"))["development"])
        .to include("issuer" => "http://localhost:9000/application/o/my-app/", "client_id" => "my-app")
    end

    it "prints the entry points under the mount and what is left to do" do
      output = run_generator([ "--mount-path", "/sso" ])

      expect(output).to include("GET    /sso/login", "GET    /sso/callback", "DELETE /sso/logout")
      expect(output).to include("pcm up authentik", "http://localhost:3000/sso/callback",
                                "PARTITIA_COGNITO_CLIENT_SECRET")
    end

    it "changes nothing and asks nothing on a second run" do
      run_generator
      before = snapshot

      output = run_generator

      expect(snapshot).to eq(before)
      expect(output).to include("already mounts Partitia::Cognito::Engine",
                                "config/initializers/partitia_cognito.rb exists",
                                "config/partitia_cognito.yml exists",
                                "already filters code, state")
    end
  end

  it "keeps a host's own initializer and yml" do
    write("config/initializers/filter_parameter_logging.rb", filter_logging)
    write("config/initializers/partitia_cognito.rb", "# mine\n")
    write("config/partitia_cognito.yml", "development: {}\n")

    run_generator

    expect(read("config/initializers/partitia_cognito.rb")).to eq("# mine\n")
    expect(read("config/partitia_cognito.yml")).to eq("development: {}\n")
  end

  it "adds only the param that is missing" do
    write("config/initializers/filter_parameter_logging.rb",
          filter_logging.sub(":passw,", ":state, :passw,"))

    run_generator

    content = read("config/initializers/filter_parameter_logging.rb")
    expect(content.scan(":state").size).to eq(1)
    expect(content).to include("  :code,\n")
  end

  it "appends a filter line when the host's file has no bracketed list" do
    write("config/initializers/filter_parameter_logging.rb",
          "Rails.application.config.filter_parameters += %i[passw]\n")

    run_generator

    expect(read("config/initializers/filter_parameter_logging.rb"))
      .to end_with("Rails.application.config.filter_parameters += %i[code state]\n")
  end

  it "creates the filter file when the host has none" do
    run_generator

    expect(read("config/initializers/filter_parameter_logging.rb"))
      .to include("Rails.application.config.filter_parameters += %i[code state]")
  end
end
