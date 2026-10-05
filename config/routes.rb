# frozen_string_literal: true

PocketPhone::Engine.routes.draw do
  # --- the phone ------------------------------------------------------------
  root to: "conversations#index"
  get  "state"                        => "conversations#state"
  post "clear"                        => "conversations#clear", as: :clear
  post "conversations"                => "conversations#create", as: :conversations
  get  "conversations/:id"            => "conversations#show", as: :conversation
  post "conversations/:id/delete"     => "conversations#destroy", as: :delete_conversation
  post "conversations/:id/typing"     => "conversations#typing"
  post "conversations/:id/messages"   => "messages#create", as: :conversation_messages
  post "messages/:handle/reactions"   => "messages#react"
  post "messages/:handle/redeliver"   => "messages#redeliver"
  post "people"                       => "people#update", as: :people
  get  "media/:name"                  => "media#show", as: :media, constraints: { name: %r{[^/]+} }

  # --- the fake Sendblue API ------------------------------------------------
  # Point your Sendblue client's base URL at wherever this engine is mounted
  # and these answer in place of https://api.sendblue.com.
  scope defaults: { format: :json } do
    post   "api/send-message"                  => "sendblue#send_message"
    post   "api/send-group-message"            => "sendblue#send_group_message"
    post   "api/send-carousel"                 => "sendblue#send_carousel"
    post   "api/send-typing-indicator"         => "sendblue#send_typing_indicator"
    post   "api/send-reaction"                 => "sendblue#send_reaction"
    post   "api/mark-read"                     => "sendblue#mark_read"
    post   "api/modify-group"                  => "sendblue#modify_group"
    get    "api/evaluate-service"              => "sendblue#evaluate_service"
    post   "api/upload-file"                   => "sendblue#upload_file"
    post   "api/upload-media-object"           => "sendblue#upload_media_object"
    post   "api/v2/contact-sharing/profile"    => "sendblue#contact_profile"
    post   "api/v2/contact-profile"            => "sendblue#contact_profile"
    get    "api/v2/messages"                   => "sendblue#messages"
    get    "api/v2/messages/:handle"           => "sendblue#message"
    delete "api/v2/messages/:handle"           => "sendblue#delete_message"
    delete "api/message/:handle"               => "sendblue#delete_message"
    match  "api/*path"                         => "sendblue#missing", via: :all
    match  "accounts/*path"                    => "sendblue#missing", via: :all
  end
end
