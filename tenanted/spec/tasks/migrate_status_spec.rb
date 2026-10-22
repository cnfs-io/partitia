require "rails_helper"
require "rake"
require "partitia/tenanted/migration_status"

RSpec.describe "partitia:tenanted:migrate:status", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("partitia:tenanted:migrate:status")
  end

  let(:task) { Rake::Task["partitia:tenanted:migrate:status"] }
  let(:global_version) { "20260601033001" }

  before { task.reenable }
  after { ENV.delete("ARTENANT") }

  def output_of_task
    capture = StringIO.new
    original = $stdout
    $stdout = capture
    task.invoke
    capture.string
  ensure
    $stdout = original
  end

  # Mark one applied tenant migration as pending, behind activerecord-tenanted's back.
  def unapply_first_migration(handle)
    path = Rails.root.join("storage/test/#{handle}.sqlite3").to_s
    db = SQLite3::Database.new(path)
    version = db.get_first_value("SELECT version FROM schema_migrations ORDER BY version")
    db.execute("DELETE FROM schema_migrations WHERE version = ?", [ version ])
    db.close
    version
  end

  it "prints the global, platform and each tenant database, in that order" do
    Partitia::Tenanted.provision_platform!(owner_email: "root@platform.test")
    tenant = create_tenant!(subdomain: "acme")

    output = output_of_task

    expect(output).to match(
      /^global: storage\/test\.sqlite3$.*^platform \(reserved\): storage\/test\/platform\.sqlite3$.*^tenant #{tenant.handle} \(acme\): storage\/test\/#{tenant.handle}\.sqlite3$/m
    )
    expect(output).to match(/^\s+up\s+#{global_version}\s+Create partitia tenanted tenants$/)
    expect(output).to include(" Status   Migration ID    Migration Name")
    expect(output).to match(/^3 databases; none pending$/)
  end

  it "reports pending tenant migrations as down without raising PendingMigrationError" do
    tenant = create_tenant!(subdomain: "acme")
    version = unapply_first_migration(tenant.handle)

    output = output_of_task

    expect(output).to match(/^\s+down\s+#{version}\s/)
    expect(output).to match(/pending: tenant #{tenant.handle} \(acme\) \(1\)$/)
  end

  it "limits the report to one database with ARTENANT" do
    tenant = create_tenant!(subdomain: "acme")
    create_tenant!(subdomain: "other")
    ENV["ARTENANT"] = tenant.handle

    output = output_of_task

    expect(output).to include("tenant #{tenant.handle} (acme)")
    expect(output).not_to include("global:", "other")
    expect(output).to match(/^1 database; none pending$/)
  end

  it "aborts on an unknown ARTENANT, listing the known databases" do
    ENV["ARTENANT"] = "nope"

    expect { task.invoke }.to raise_error(SystemExit).and output(/No database "nope". Known: global/).to_stderr
  end

  describe Partitia::Tenanted::MigrationStatus do
    it "reports a database that doesn't exist yet as not created, without creating it" do
      config = described_class.tenant_config("ghost")

      report = described_class.report("tenant ghost", config)

      expect(report.rows).to be_nil
      expect(File).not_to exist(Rails.root.join("storage/test/ghost.sqlite3"))
      expect(described_class.summary([ report ])).to eq("1 database; none pending; not created: tenant ghost")
    end

    it "reports every migration pending on a database nothing has migrated yet" do
      path = Rails.root.join("storage/test/blank.sqlite3")
      path.dirname.mkpath
      SQLite3::Database.new(path.to_s).close

      report = described_class.report("tenant blank", described_class.tenant_config("blank"))

      expect(report.rows).not_to be_empty
      expect(report.rows.map(&:first).uniq).to eq([ "down" ])
    ensure
      FileUtils.rm_f(path)
    end
  end
end
