# frozen_string_literal: true
#
# Tenant-aware migration status for ActiveRecord::Tenanted.
#
# activerecord-tenanted ships db:migrate:<dbname> (e.g. db:migrate:primary) but
# not a matching status task. This fills that gap and — crucially — works even
# when a tenant has PENDING migrations, which is exactly when you most want
# status (e.g. a pre-deploy check in prod).
#
# Usage:
#   ARTENANT=apple rails db:migrate:status_primary   # one tenant
#   rails db:migrate:status_all                      # every tenant, looped
#
# Naming: Rake cannot nest a namespace under an existing task, and
# `db:migrate:primary` is already a task — so `db:migrate:primary:status` is
# impossible to define. status_primary is the closest collision-free form.
#
# Why not ApplicationRecord.with_tenant? The gem deliberately raises
# PendingMigrationError when it opens a connection pool for a tenant with
# unapplied migrations. That makes with_tenant unusable for status-while-pending.
# Instead we open our OWN temporary connection pool pointed at the tenant's
# database file — the technique Rails core uses internally for pending checks —
# which bypasses the gem's managed-pool guard. We depend on :load_config (not
# :environment) so booting the app doesn't arm Rails' boot-time pending check.

namespace :db do
  namespace :migrate do
    desc "Migration status for one tenant of the :primary DB (set ARTENANT=<tenant>)"
    task status_primary: :load_config do
      tenant = ENV["ARTENANT"]
      abort "Set ARTENANT=<tenant_name>, e.g. ARTENANT=apple rails db:migrate:status_primary" if tenant.nil? || tenant.empty?

      tenants = CnfsTenanted::MigrationStatus.tenant_names
      unless tenants.include?(tenant)
        abort "Tenant #{tenant.inspect} does not exist. Known tenants: #{tenants.join(', ')}"
      end

      CnfsTenanted::MigrationStatus.print(tenant)
    end

    desc "Migration status for every tenant of the :primary DB"
    task status_all: :load_config do
      tenants = CnfsTenanted::MigrationStatus.tenant_names
      if tenants.empty?
        puts "No tenants found."
        next
      end

      tenants.each do |t|
        CnfsTenanted::MigrationStatus.print(t)
        puts
      end
    end
  end
end
