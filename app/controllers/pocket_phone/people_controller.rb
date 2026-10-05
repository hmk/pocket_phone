# frozen_string_literal: true

module PocketPhone
  # The fake people: their names, whether they have an iPhone, and what
  # becomes of a message sent to them.
  class PeopleController < ApplicationController
    def update
      number = Numbers.normalize(params[:number])
      unless number.empty?
        store.write do |db|
          person = db.ensure_person(number, "service" => params[:service], "outcome" => params[:outcome])
          person["name"] = params[:name].to_s.strip.presence if params.key?(:name)
        end
      end

      request.xhr? ? head(:no_content) : redirect_back(fallback_location: root_path)
    end
  end
end
