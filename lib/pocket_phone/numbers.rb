# frozen_string_literal: true

module PocketPhone
  module Numbers
    E164 = /\A\+[1-9]\d{6,14}\z/
    EMAIL = /\A[^@\s]+@[^@\s]+\z/

    module_function

    # What the UI accepts: anything a person might type. "555 123 4567" becomes
    # +15551234567; an iMessage email address is kept as it is.
    def normalize(value)
      text = value.to_s.strip
      return text.downcase if text.include?("@")

      digits = text.gsub(/\D/, "")
      return "" if digits.empty?
      return "+#{digits}" if text.start_with?("+")

      digits.length == 10 ? "+1#{digits}" : "+#{digits}"
    end

    # What the API accepts: Sendblue takes E.164 (or an email) and nothing else.
    def valid?(value)
      text = value.to_s
      text.match?(E164) || text.match?(EMAIL)
    end

    def pretty(number)
      text = number.to_s
      match = text.match(/\A\+1(\d{3})(\d{3})(\d{4})\z/)
      match ? "+1 (#{match[1]}) #{match[2]}-#{match[3]}" : text
    end

    # A number nobody owns, for the "new person" form.
    def random
      format("+1555555%04d", rand(100..9999))
    end
  end
end
