module Iam
  # Binds an IdP identity to a human principal (ADR 0004). The `(issuer, subject)`
  # pair is unique per database; a principal may hold many links (Google +
  # passkey + Apple → one canonical id). This is the ONLY place the IdP `subject`
  # (`sub`) is stored — nothing else in the system references it.
  class IdentityLink < ApplicationRecord
    belongs_to :principal, class_name: "Iam::Principal"

    validates :issuer, presence: true
    validates :subject, presence: true, uniqueness: { scope: :issuer }
    validate :principal_is_human
    # Make a duplicate-login race visible without logging the subject (IdP sub).
    after_validation :log_duplicate_link

    private

    def log_duplicate_link
      return unless errors.of_kind?(:subject, :taken)

      logger.debug { "identity link duplicate: issuer=#{issuer} (login race)" }
    end

    # Machines authenticate via credentials, never via IdP assertions, so an
    # identity link may only bind to a human principal.
    def principal_is_human
      return if principal.is_a?(Iam::HumanPrincipal)

      errors.add(:principal, I18n.t("iam.identity_link.errors.not_human"))
    end
  end
end
