require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"

# Spec for the `cnfs_tenanted:install:global_migrations` rake task.
#
# The task copies GLOBAL migrations (the non-standard db/global_migrate scope
# that Rails' own install:migrations tasks don't see) from every registered
# engine's CnfsSupport.migrations_paths[:global] into the host's
# db/global_migrate. Here we drive both the source (a controlled fixture dir)
# and the destination (a tmpdir) so the real dummy tree is never touched.
RSpec.describe "cnfs_tenanted:install:global_migrations", type: :task do
  # Load the app's rake tasks once (they include lib/tasks/*.rake via the
  # engine), then re-enable the task before each example so it can run again —
  # rake tasks execute at most once per process by default.
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("cnfs_tenanted:install:global_migrations")
  end

  let(:task) { Rake::Task["cnfs_tenanted:install:global_migrations"] }

  # A tmp destination standing in for the host's db/global_migrate, and a tmp
  # source dir shaped like <engine_root>/db/global_migrate so the task's
  # scope-label derivation (parent.parent.basename) yields a clean label.
  let(:tmp_root)    { Pathname.new(Dir.mktmpdir) }
  let(:destination) { tmp_root.join("host/db/global_migrate") }
  let(:source_dir)  { tmp_root.join("acme_engine/db/global_migrate") }

  before do
    task.reenable

    FileUtils.mkdir_p(source_dir)
    File.write(source_dir.join("20260101000000_create_widgets.rb"), <<~RUBY)
      class CreateWidgets < ActiveRecord::Migration[8.1]
        def change
          create_table :widgets
        end
      end
    RUBY

    # Point the task at our fixtures: it reads the source list from the registry
    # and computes the destination from Rails.root + the :global search path.
    allow(CnfsSupport).to receive(:migrations_paths)
      .and_return(global: [ source_dir.to_s ])
    allow(Rails).to receive(:root).and_return(tmp_root.join("host"))
    # migrations_paths_for.fetch(:global) -> "db/global_migrate" (real value is
    # fine; the destination becomes tmp_root/host/db/global_migrate).
  end

  after do
    FileUtils.remove_entry(tmp_root) if tmp_root.exist?
  end

  it "copies global migrations from the registry into the host db/global_migrate" do
    expect { task.invoke }.to output(/Copied 1 global migration/).to_stdout

    copied = Dir.children(destination)
    expect(copied.size).to eq(1)
    # Rails' Migration.copy suffixes the file with the scope (engine dir name).
    expect(copied.first).to match(/create_widgets\.acme_engine\.rb\z/)
  end

  it "stamps the copied migration with its originating scope" do
    task.invoke

    body = File.read(destination.join(Dir.children(destination).first))
    expect(body).to include("This migration comes from acme_engine")
  end

  it "is idempotent — a second run copies nothing" do
    task.invoke
    task.reenable

    expect { task.invoke }.to output(/already present/).to_stdout
    expect(Dir.children(destination).size).to eq(1)
  end

  context "when no global migrations are registered" do
    before do
      allow(CnfsSupport).to receive(:migrations_paths).and_return(global: nil)
    end

    it "no-ops without creating the destination" do
      expect { task.invoke }.to output(/nothing to copy/).to_stdout
      expect(destination.exist?).to be(false)
    end
  end
end
