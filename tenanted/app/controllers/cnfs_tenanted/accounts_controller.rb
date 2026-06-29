module CnfsTenanted
  # The tenant's self-service settings singleton, served on the tenant's
  # subdomain. Always operates on Account.instance — there is no id, because
  # there is exactly one Account per tenant database.
  #
  # Routed as a singular resource (resource :account), so:
  #   GET   /account       -> show
  #   GET   /account/edit  -> edit
  #   PATCH /account       -> update
  #
  # Host gets a thin subclass via the install generator:
  #   class AccountsController < CnfsTenanted::AccountsController; end
  class AccountsController < ::ApplicationController
    before_action :set_account

    def show
    end

    def edit
    end

    def update
      respond_to do |format|
        if @account.update(account_params)
          format.html { redirect_to account_path, notice: "Account was successfully updated.", status: :see_other }
          format.json { render :show, status: :ok, location: account_path }
        else
          format.html { render :edit, status: :unprocessable_content }
          format.json { render json: @account.errors, status: :unprocessable_content }
        end
      end
    end

    private

    # The singleton for the current tenant. Created on first access if missing,
    # though in practice Tenant#after_create has already seeded it.
    def set_account
      @account = Account.instance
    end

    def account_params
      params.expect(account: [ :name ])
    end
  end
end
