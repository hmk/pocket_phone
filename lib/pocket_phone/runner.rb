# frozen_string_literal: true

module PocketPhone
  # Where work that must not hold up a request goes. Sendblue answers a send
  # straight away and reports what happened later; so does this.
  module Runner
    module_function

    def run(&block)
      return block.call unless PocketPhone.config.async

      Thread.new do
        block.call
      rescue StandardError => e
        log("#{e.class}: #{e.message}")
      end
    end

    def pause(seconds)
      sleep(seconds) if PocketPhone.config.async && seconds.to_f.positive?
    end

    # For the moments a background thread touches the host app's code (a
    # configured lambda reading a model). Kept short on purpose: the thread
    # must not be inside the executor while it calls the app over HTTP, or a
    # code reload waiting on it would wait on itself.
    def with_app(&block)
      app = defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      app ? app.executor.wrap(&block) : block.call
    end

    def log(message)
      logger = defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      logger&.warn("[pocket_phone] #{message}")
    end
  end
end
