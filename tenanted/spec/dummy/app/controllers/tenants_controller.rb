# Host subclass of the engine's tenant-registry CRUD (the platform console
# seed). Behavior — including the platform_console_guard before_action — lives
# in CnfsTenanted::TenantsController.
class TenantsController < CnfsTenanted::TenantsController
end
