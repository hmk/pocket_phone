# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"

module PocketPhone
  # The database on disk: one JSON file under tmp/, guarded by a lock file so
  # the web server, its background threads and anything else that loads the
  # gem can all read and write it safely.
  class Store
    attr_reader :path

    def initialize(path)
      @path = path.to_s
    end

    def read
      locked(File::LOCK_SH) { Database.new(load) }
    end

    # Yields the database for changes and saves it. Returns the block's value.
    def write
      locked(File::LOCK_EX) do
        database = Database.new(load)
        seed(database)
        result = yield database
        database.data["version"] = database.version + 1
        dump(database.data)
        result
      end
    end

    # Forget every conversation. People and lines are kept, so a number you
    # set up once stays set up.
    def clear!
      write do |database|
        database.conversations.clear
        database.messages.clear
        database.previews.clear
      end
      FileUtils.rm_rf(media_dir)
    end

    # Everything, people included.
    def reset!
      locked(File::LOCK_EX) { FileUtils.rm_f(file) }
      FileUtils.rm_rf(media_dir)
    end

    # --- attachments --------------------------------------------------------

    def media_dir = File.join(path, "media")

    def save_media(io, filename)
      FileUtils.mkdir_p(media_dir)
      name = "#{SecureRandom.hex(8)}#{File.extname(filename.to_s).downcase[/\A\.[a-z0-9]{1,8}\z/]}"
      File.binwrite(File.join(media_dir, name), io.read)
      name
    end

    def media_file(name)
      candidate = File.join(media_dir, File.basename(name.to_s))
      candidate if File.file?(candidate)
    end

    private

    def file = File.join(path, "store.json")

    def locked(mode)
      FileUtils.mkdir_p(path)
      File.open(File.join(path, "store.lock"), File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(mode)
        yield
      end
    end

    def load
      File.exist?(file) ? JSON.parse(File.read(file)) : nil
    rescue JSON::ParserError
      nil
    end

    # Written beside the real file and renamed over it, so a reader never sees
    # half a database.
    def dump(data)
      temporary = "#{file}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.write(temporary, JSON.generate(data))
      File.rename(temporary, file)
    end

    def seed(database)
      return if database.data["seeded"]

      database.data["seeded"] = true
      Array(PocketPhone.config.people).each do |person|
        person = person.transform_keys(&:to_s)
        number = Numbers.normalize(person["number"])
        next if number.empty?

        database.ensure_person(number, person.slice("name", "service", "outcome"))
      end
    end
  end
end
