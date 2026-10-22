require "rails_helper"
require "rails/generators"
require "generators/partitia/tenanted/install/install_generator"
require "tmpdir"

RSpec.describe Partitia::Tenanted::Generators::InstallGenerator do
  let(:app) { Pathname.new(Dir.mktmpdir("tenanted-install")) }
  let(:railties_templates) do
    Pathname.new(Gem.loaded_specs.fetch("railties").full_gem_path)
      .join("lib/rails/generators/rails/app/templates")
  end

  # config/database.yml exactly as `rails new` (SQLite) renders it, from
  # railties' own template, for the given option variant.
  def stock_database_yml(skip_solid: false, skip_kamal: false, skip_action_cable: false)
    options = Struct.new(:skip_solid?, :skip_kamal?, :skip_action_cable?)
                    .new(skip_solid, skip_kamal, skip_action_cable)
    source = railties_templates.join("config/databases/sqlite3.yml.tt").read
    ERB.new(source, trim_mode: "-").result_with_hash(options: options)
  end

  def write(path, content)
    app.join(path).dirname.mkpath
    app.join(path).write(content)
  end

  def run_generator
    generator = described_class.new([], {}, destination_root: app.to_s)
    allow(generator).to receive(:rails_command)
    output = capture_stdout { generator.invoke_all }
    [ generator, output ]
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def snapshot
    Dir.glob("**/*", base: app.to_s).sort.select { |f| app.join(f).file? }
       .to_h { |f| [ f, app.join(f).read ] }
  end

  before do
    # Any prompt (a Thor file collision) is a failure: the generator must never ask.
    allow(Thor::LineEditor).to receive(:readline).and_raise("generator asked a question")

    write "app/models/application_record.rb", <<~RUBY
      class ApplicationRecord < ActiveRecord::Base
        primary_abstract_class
      end
    RUBY
    write "app/controllers/application_controller.rb", <<~RUBY
      class ApplicationController < ActionController::Base
        allow_browser versions: :modern
      end
    RUBY
    write "config/environments/development.rb", <<~RUBY
      require "active_support/core_ext/integer/time"

      Rails.application.configure do
        config.enable_reloading = true
      end
    RUBY
    write "config/application.rb", <<~RUBY
      module Fresh
        class Application < Rails::Application
          config.load_defaults 8.1
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(app) }

  def database_config
    yaml = app.join("config/database.yml").read.gsub(/<%=.*?%>/m, "ERB")
    YAML.safe_load(yaml, aliases: true)
  end

  context "on a fresh `rails new` app" do
    before { write "config/database.yml", stock_database_yml }

    it "wires every environment with a global and a tenanted plane from the registry" do
      run_generator

      raw = app.join("config/database.yml").read
      expect(raw).to include("<%= Partitia::Support.migrations_paths[:global] %>")
      expect(raw).to include("<%= Partitia::Support.migrations_paths[:tenant] %>")

      config = database_config
      %w[development test production].each do |env|
        expect(config[env]["global"]).to include("database" => "storage/#{env}.sqlite3", "migrations_paths" => "ERB")
        expect(config[env]["tenant"]).to include("database" => "storage/#{env}/%{tenant}.sqlite3",
                                                 "migrations_paths" => "ERB", "tenanted" => true)
      end
    end

    it "keeps the stock Solid databases in production" do
      run_generator

      production = database_config["production"]
      expect(production.keys).to eq(%w[global tenant cache queue cable])
      expect(production["queue"]).to include("database" => "storage/production_queue.sqlite3",
                                             "migrations_paths" => "db/queue_migrate")
    end

    it "wires ApplicationRecord, ApplicationController, subdomains, controllers and the initializer" do
      run_generator

      expect(app.join("app/models/application_record.rb").read).to include(%(tenanted "tenant"))
      expect(app.join("app/controllers/application_controller.rb").read)
        .to include("include Partitia::Tenanted::TenantResolution")
      expect(app.join("config/environments/development.rb").read).to include("tld_length = 0")
      expect(app.join("app/controllers/tenants_controller.rb")).to exist
      expect(app.join("app/controllers/tenant_not_found_controller.rb")).to exist
      expect(app.join("config/initializers/partitia_tenanted.rb").read).to include("platform_console_guard")
    end

    it "leaves the migration scopes to the engine (nothing registered in application.rb)" do
      run_generator

      expect(app.join("config/application.rb").read).not_to include("migrations_paths_for")
    end

    it "migrates the global database" do
      generator, = run_generator

      expect(generator).to have_received(:rails_command).with("db:migrate")
    end

    it "prints the entry points and what the host still has to do" do
      _, output = run_generator

      expect(output).to include("/tenants", "/tenant-unknown", "platform_console_guard",
                                "provision_platform!", "partitia:tenanted:migrate:status")
    end

    it "changes nothing and asks nothing on a second run" do
      run_generator
      before = snapshot

      _, output = run_generator

      expect(snapshot).to eq(before)
      expect(output).not_to match(/^\s+(create|force|conflict|insert|append)\s/)
    end
  end

  context "with the stock file's variants" do
    it "recognises --skip-solid (single production database)" do
      write "config/database.yml", stock_database_yml(skip_solid: true)
      run_generator

      expect(database_config["production"].keys).to eq(%w[global tenant])
    end

    it "recognises --skip-kamal --skip-action-cable" do
      write "config/database.yml", stock_database_yml(skip_kamal: true, skip_action_cable: true)
      run_generator

      expect(database_config["production"].keys).to eq(%w[global tenant cache queue])
    end
  end

  context "when there is no database.yml" do
    it "writes the tenanted layout" do
      run_generator

      expect(database_config["test"]["tenant"]["tenanted"]).to be(true)
    end
  end

  context "when database.yml already has the tenanted layout" do
    let(:custom_tenanted) do
      Rails.root.join("config/database.yml").read + "\n# hand edit kept\n"
    end

    it "leaves it as it is" do
      write "config/database.yml", custom_tenanted
      _, output = run_generator

      expect(app.join("config/database.yml").read).to eq(custom_tenanted)
      expect(output).to match(/skip.*already has the global and tenant planes/)
    end
  end

  context "when database.yml is customized" do
    let(:custom) { stock_database_yml.sub("timeout: 5000", "timeout: 10000") }

    before { write "config/database.yml", custom }

    it "stops before changing any file and prints the layout to adopt" do
      before = snapshot

      expect { capture_stdout { run_generator } }.to raise_error(Thor::Error, /customized; not changed/)
      expect(snapshot).to eq(before)
    end

    it "names the environments to change and shows the tenanted blocks" do
      generator = described_class.new([], {}, destination_root: app.to_s)
      output = capture_stdout do
        expect { generator.configure_database }.to raise_error(Thor::Error)
      end

      expect(output).to include("development, test, production")
      expect(output).to include("tenanted: true", "<%= Partitia::Support.migrations_paths[:global] %>")
    end

    it "treats a file wired for development only as customized" do
      partial = Rails.root.join("config/database.yml").read
                     .sub(/^test:.*\z/m, "test:\n  <<: *default\n  database: storage/test.sqlite3\n")
      write "config/database.yml", partial

      generator = described_class.new([], {}, destination_root: app.to_s)
      output = capture_stdout do
        expect { generator.configure_database }.to raise_error(Thor::Error)
      end
      expect(output).to include("lack the global and tenant databases:\ntest, production\n")
      expect(app.join("config/database.yml").read).to eq(partial)
    end
  end
end
