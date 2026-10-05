# frozen_string_literal: true

module PocketPhone
  # Attachments sent from the phone, or uploaded through the fake API. Served
  # from here so a media_url in a webhook is one the app can really fetch.
  class MediaController < ApplicationController
    def show
      file = store.media_file(params[:name])
      return head(:not_found) unless file

      send_file file, disposition: "inline"
    end
  end
end
