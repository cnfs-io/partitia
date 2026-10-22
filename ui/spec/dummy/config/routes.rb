Rails.application.routes.draw do
  mount CnfsUi::Engine => "/cnfs_ui"
  mount Lookbook::Engine => "/lookbook"
end
