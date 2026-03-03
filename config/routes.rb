# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Authentication
  resource :session
  resources :sessions, only: :destroy, as: :user_session
  resources :passwords, param: :token
  get "login", to: "sessions#new"
  delete "logout", to: "sessions#destroy"
  get "signup", to: "registrations#new"
  post "signup", to: "registrations#create"

  scope "login" do
    resource :two_factor_challenge, only: %i[new create], path: "verify"
  end

  resource :profile, only: %i[edit update destroy]
  resource :two_factor_setup, only: %i[new create destroy]

  # Notifications
  resources :notifications, only: :index do
    resource :read, only: :create, module: :notifications
  end
  resource :notification_reads, only: :create
  resource :notification_clears, only: :create

  # Sidebar
  resources :sidebar_groups, only: %i[create update destroy] do
    scope module: :sidebar_groups do
      resources :memberships, only: %i[create destroy]
      resource :positions
    end
  end
  resource :sidebar_positions, only: :update

  # Tools
  resources :tools do
    scope module: :tools do
      resources :collaborators, only: %i[create update destroy] do
        delete :leave, on: :collection
      end

      resource :board, only: :show do
        scope module: :boards do
          resources :columns, only: %i[create update destroy]
          resource :positions, only: :update
          resources :cards, only: %i[show update destroy] do
            scope module: :cards do
              resources :comments, only: %i[create destroy]
              resources :attachments, only: %i[create destroy]
              resource :archive, only: %i[create destroy]
            end
          end
        end
      end

      resource :files, only: :show, controller: "files" do
        scope module: :files do
          resources :folders, only: %i[create update destroy] do
            scope module: :folders do
              resource :download, only: :show
              resource :share, only: %i[show create destroy]
            end
          end
          resources :items, only: %i[show update destroy] do
            scope module: :items do
              resource :download, only: :show
              resource :share, only: %i[show create destroy]
            end
          end
          resources :uploads, only: :create
        end
      end

      resource :chat, only: :show do
        scope module: :chats do
          resources :messages, only: %i[create update destroy]
          resource :read, only: :create
        end
      end

      resource :docs, only: :show, controller: "docs" do
        scope module: :docs do
          resources :documents, only: %i[show edit create update destroy]
        end
      end

      resources :mails, only: %i[index show new create destroy]

      resource :mails_account, only: %i[new create update], path: "mails/account", controller: "mails/accounts" do
        post :test_connection, on: :collection
      end

      # Mail state controllers (RESTful)
      scope module: :mails do
        resource :sync, only: %i[show create], controller: "syncs"
        resource :bulk, only: :create, controller: "bulk_actions"
        resource :folder, only: :create, controller: "folders"
        delete "trash", to: "trashes#destroy_all", as: :empty_trash
      end

      resources :mails, only: [] do
        scope module: :mails do
          resource :read, only: %i[create destroy]
          resource :star, only: %i[create destroy]
          resource :archive, only: %i[create destroy]
          resource :trash, only: %i[create destroy]
          resource :move, only: :create
        end
      end

      resources :mail_labels, only: %i[index create update destroy]

      resources :mails_contacts, only: :index, controller: "mails/contacts"

      resource :room, only: :show do
        scope module: :rooms do
          resources :tokens, only: :create
        end
      end

      resource :todo, only: :show do
        scope module: :todos do
          resources :lists, only: %i[create update destroy]
          resource :positions, only: :update
          resources :items, only: %i[show update destroy] do
            scope module: :items do
              resources :comments, only: %i[create destroy]
              resources :attachments, only: %i[create destroy]
              resource :completion, only: %i[create destroy]
            end
          end
        end
      end

      resource :calendar, only: :show do
        scope module: :calendars do
          resource :account, only: %i[new create edit update] do
            post :test_connection, on: :collection
          end
          resource :sync, only: %i[show create]
          resources :events, only: %i[show new create edit update destroy]
          resources :invites, only: %i[create destroy]
        end
      end
      post   "invitations/:id/resend", to: "invitations#resend", as: :resend_invitation
      delete "invitations/:id",        to: "invitations#cancel", as: :cancel_invitation
    end
  end

  # Columns (nested under tools for card creation)
  resources :columns, only: [] do
    scope module: :columns do
      resources :cards, only: :create
      resource :positions, only: :update
    end
  end

  # Todo lists (nested under tools for item creation)
  resources :todo_lists, only: [] do
    scope module: :todo_lists do
      resources :items, only: :create
      resource :positions, only: :update
    end
  end


  # Public sharing
  scope :s do
    resources :shares, only: :show, param: :token, path: "", controller: "tools/files/shares" do
      scope module: "tools/files/shares" do
        resource :download, only: :show
        resources :files, only: :show
      end
    end
  end

  get "invitations/:token/accept", to: "invitation_acceptances#show", as: :invitation_acceptance
  post "invitations/:token/accept", to: "invitation_acceptances#create"
  delete "invitations/:token/accept", to: "invitation_acceptances#destroy"

  root "dashboard#index"
end
