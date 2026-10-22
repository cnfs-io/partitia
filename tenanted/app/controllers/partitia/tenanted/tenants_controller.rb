module CnfsTenanted
  # Global-admin CRUD for the tenant registry. Served on the bare domain.
  #
  # The host app gets a thin subclass via the install generator:
  #   class TenantsController < CnfsTenanted::TenantsController; end
  # so routes resolve to the host's namespace while behavior lives here.
  # To customize, the host overrides actions in its subclass (calling super or
  # replacing) and/or ejects the views with the eject generator.
  class TenantsController < ::ApplicationController
    # The seed of the platform console (ADR 0003 §7): the tenant registry CRUD
    # is a platform-plane operation, so every action runs behind the platform
    # console guard. The guard is a host-configured callable run in controller
    # context; it defaults to DENY, so an unconfigured console is a closed one.
    before_action :guard_platform_console
    before_action :set_tenant, only: %i[ show edit update destroy ]

    def index
      @tenants = Tenant.all
    end

    def show
    end

    def new
      @tenant = Tenant.new
    end

    def edit
    end

    def create
      @tenant = Tenant.new(tenant_params)

      respond_to do |format|
        if @tenant.save
          format.html { redirect_to @tenant, notice: "Tenant was successfully created." }
          format.json { render :show, status: :created, location: @tenant }
        else
          format.html { render :new, status: :unprocessable_content }
          format.json { render json: @tenant.errors, status: :unprocessable_content }
        end
      end
    end

    def update
      respond_to do |format|
        if @tenant.update(tenant_params)
          format.html { redirect_to @tenant, notice: "Tenant was successfully updated.", status: :see_other }
          format.json { render :show, status: :ok, location: @tenant }
        else
          format.html { render :edit, status: :unprocessable_content }
          format.json { render json: @tenant.errors, status: :unprocessable_content }
        end
      end
    end

    def destroy
      @tenant.destroy!

      respond_to do |format|
        format.html { redirect_to tenants_path, notice: "Tenant was successfully destroyed.", status: :see_other }
        format.json { head :no_content }
      end
    end

    private

    def set_tenant
      @tenant = Tenant.find(params.expect(:id))
    end

    def tenant_params
      params.expect(tenant: [ :name, :subdomain, :owner_email ])
    end

    # Run the configured platform console guard in this controller's context so
    # it can redirect_to/render/head as it decides. Rendering or redirecting
    # halts the action; doing nothing lets it proceed. The default guard denies
    # with 403 (see CnfsTenanted::DEFAULT_CONSOLE_GUARD).
    def guard_platform_console
      instance_exec(&CnfsTenanted.platform_console_guard)
    end
  end
end
