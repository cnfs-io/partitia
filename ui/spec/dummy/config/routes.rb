Rails.application.routes.draw do
  mount Partitia::Ui::Engine => "/partitia_ui"
  mount Lookbook::Engine => "/lookbook"
end
