# The one demonstration policy (Plan 004 WS1.4): authorization keys off the
# resolved canonical principal and fails closed when there is none.
class DashboardPolicy < Struct.new(:user, :record)
  def show?
    user.present?
  end
end
