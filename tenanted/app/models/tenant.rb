# The global tenant registry. One row per tenant, living in the `global`
# database. Carries the routing and lifecycle facts the platform holds *about* a
# tenant (ADR 0003 §4) — never identity, which lives inside the tenant's own
# database (ADR 0003 §6).
#
# ROUTING KEY (ADR 0002 §1/§5): the database is keyed by `handle` — an opaque,
# system-generated, immutable string. `subdomain` is the mutable, human-facing
# value a request resolves *to* a handle; it is a lookup onto the handle, never
# the handle itself. Rebrands move the subdomain, never the handle.
#
# Top-level namespace by design (see GlobalRecord).
class Tenant < GlobalRecord
  # Lowercased Crockford base32, with visually ambiguous characters excluded
  # (0/1/i/l/o/u). A routing fact, not a branding surface.
  HANDLE_ALPHABET = ((("a".."z").to_a - %w[i l o u]) + ("2".."9").to_a).freeze
  HANDLE_LENGTH = 8

  validates :name, :subdomain, :owner_email, presence: true
  validates :subdomain, uniqueness: true
  validates :handle, presence: true, uniqueness: true
  validate :handle_is_immutable, on: :update
  validate :handle_and_subdomain_are_not_reserved

  before_validation :assign_handle, on: :create

  # Provision the tenant's own database immediately after the registry row is
  # created, then run the after_provision hook registry inside it (identity
  # seeding is registered there by the iam engine). A hook raise aborts: the
  # created database is dropped and this after_create transaction rolls back, so
  # a tenant that fails to seed never exists (ADR 0003 §6).
  after_create :provision_tenant

  private

  # Generate a unique, non-reserved handle on create. Retries on the (vanishing)
  # chance of a collision and never emits the reserved platform handle.
  def assign_handle
    return if handle.present?

    self.handle =
      loop do
        candidate = generate_handle_candidate
        next if candidate == CnfsTenanted::RESERVED_HANDLE
        break candidate unless self.class.exists?(handle: candidate)
      end
  end

  def generate_handle_candidate
    Array.new(HANDLE_LENGTH) { HANDLE_ALPHABET.sample }.join
  end

  def handle_is_immutable
    errors.add(:handle, "is immutable and cannot be changed") if handle_changed?
  end

  def handle_and_subdomain_are_not_reserved
    if handle == CnfsTenanted::RESERVED_HANDLE
      errors.add(:handle, "cannot be the reserved platform handle")
    end
    if subdomain == CnfsTenanted::RESERVED_HANDLE
      errors.add(:subdomain, "cannot be the reserved platform handle")
    end
  end

  def provision_tenant
    CnfsTenanted.run_provision(handle, self, cleanup_on_failure: true)
  end
end
