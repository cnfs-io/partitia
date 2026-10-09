class HomeController < ApplicationController
  # Surfaces any flash so failure-flow specs can assert the broker's message.
  def show
    render plain: [ flash[:alert], "home" ].compact.join("\n")
  end
end
