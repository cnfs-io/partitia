class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # The dummy app is a tenanted host, exactly as the install generator wires a
  # real one. activerecord-tenanted's test integration resolves this class as
  # its connection_class and drives current_tenant / tenant genesis through it,
  # so it must actually be tenanted or the suite fails at boot.
  #
  # The argument is the database.yml config name of the tenanted database. We
  # renamed it from the adapter's default "primary" to "tenant", so it must be
  # passed explicitly.
  tenanted "tenant"
end
