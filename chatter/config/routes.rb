Chatter::Engine.routes.draw do
  resources :conversations, only: [ :index, :show, :create ] do
    resources :messages, only: [ :create ]
  end

  root to: "conversations#index"
end
