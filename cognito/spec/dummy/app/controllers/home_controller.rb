class HomeController < ApplicationController
  # Surfaces any flash so failure-flow request specs can assert the broker's
  # i18n message after following the redirect.
  def show
    render plain: [ flash[:alert], "home" ].compact.join("\n")
  end
end
