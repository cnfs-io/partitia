# ⚠️  DEV/TEST SCAFFOLD — written by `rails g chatter:install:dev`.
# A landing page rendered in the host layout (which carries the switcher), so you
# can pick an identity BEFORE entering /chatter. chatter's ConversationsController
# refuses (403) until current_participant is set, and the switcher lives in the
# host layout — so a host page you can always reach is where you "become" someone.
# Safe to delete when done.
class HomeController < ApplicationController
  def index
  end
end
