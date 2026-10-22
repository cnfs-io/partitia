module Partitia
  module Iam
    # Tenant-plane base record for every IAM model in this plan (Account,
    # Principal, Credential). Under multi-tenancy the host's partitia-tenanted wiring
    # makes this `subtenant_of` automatically (ADR 0003); IAM does nothing here to
    # enable that. Global-plane models (Partitia::Iam::GlobalAccount) are a later plan and
    # inherit GlobalRecord instead — not this class.
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
