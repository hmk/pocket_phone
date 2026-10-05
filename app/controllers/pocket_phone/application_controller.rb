# frozen_string_literal: true

module PocketPhone
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    layout "pocket_phone/application"

    # The page carries its own inline styles and script, like letter_opener_web;
    # a host app's policy written for its own pages would block both.
    content_security_policy(false) if respond_to?(:content_security_policy)

    before_action :remember_base_url

    private

    def store = PocketPhone.store

    def remember_base_url
      PocketPhone.base_url = request.base_url
    end

    # The line a phone texts when it starts the conversation: the one the app
    # is configured with, else one the app has already sent from.
    def default_line(database)
      Numbers.normalize(PocketPhone.config.from_number).presence ||
        database.lines.keys.first || PocketPhone::FALLBACK_LINE
    end

    def media_url_for(name)
      "#{request.base_url}#{request.script_name}/media/#{name}"
    end
  end
end
