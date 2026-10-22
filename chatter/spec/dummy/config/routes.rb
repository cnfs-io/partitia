Rails.application.routes.draw do
  mount Chatter::Engine => "/chatter"

  # Fake-auth switcher: POST a participant's GlobalID to "become" them.
  post "session", to: "session#update", as: :session

  root to: redirect("/chatter")
end
