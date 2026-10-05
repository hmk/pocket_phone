# frozen_string_literal: true

require "test_helper"

class UnitTest < PocketPhone::TestCase
  test "numbers typed by a person are tidied into E.164" do
    assert_equal "+15552223333", PocketPhone::Numbers.normalize("(555) 222-3333")
    assert_equal "+15552223333", PocketPhone::Numbers.normalize("+1 555 222 3333")
    assert_equal "+447700900123", PocketPhone::Numbers.normalize("+44 7700 900123")
    assert_equal "alice@example.com", PocketPhone::Numbers.normalize(" Alice@Example.com ")
    assert_equal "", PocketPhone::Numbers.normalize("nope")
    assert_equal "+1 (555) 222-3333", PocketPhone::Numbers.pretty("+15552223333")
  end

  test "the API only takes E.164 or an email" do
    assert PocketPhone::Numbers.valid?("+15552223333")
    assert PocketPhone::Numbers.valid?("alice@example.com")
    refute PocketPhone::Numbers.valid?("5552223333")
    refute PocketPhone::Numbers.valid?("+0155")
  end

  test "a setting given as a lambda is read each time, and blank counts as unset" do
    urls = ["http://one.test", ""]
    PocketPhone.config.webhook_url = -> { urls.shift }

    assert_equal "http://one.test", PocketPhone.config.webhook_url
    assert_nil PocketPhone.config.webhook_url
  end

  test "people named in the configuration are there on first use" do
    PocketPhone.config.people = [{ name: "Alice", number: "555 222 3333", service: "SMS" }]

    PocketPhone.store.write { |db| db.ensure_line(LINE) }

    assert_equal({ "number" => ALICE, "name" => "Alice", "service" => "SMS", "outcome" => "delivered" },
      db.people[ALICE])
  end

  test "writes from many threads at once all land" do
    store = PocketPhone.store
    conversation = store.write { |db| db.direct(LINE, ALICE) }

    20.times.map { |i|
      Thread.new do
        store.write { |db| db.add_message(db.conversations[conversation["id"]], "direction" => "app", "content" => i.to_s) }
      end
    }.each(&:join)

    assert_equal 20, db.messages.size
    assert_equal (0...20).map(&:to_s).sort, db.messages.values.map { |m| m["content"] }.sort
  end

  test "a failed write changes nothing" do
    store = PocketPhone.store
    store.write { |db| db.ensure_line(LINE) }
    version = db.version

    assert_raises(RuntimeError) { store.write { |db| db.ensure_person(ALICE) and raise "boom" } }

    assert_empty db.people
    assert_equal version, db.version
  end

  test "a webhook is signed over its exact body" do
    PocketPhone.config.signing_secret = "whsec"
    sent = nil
    stub_request(:post, WEBHOOK).with { |request| sent = request }

    result = PocketPhone::Webhook.deliver(type: "receive", url: WEBHOOK, payload: { "content" => "héllo" })

    assert_equal 200, result["status"]
    assert_equal PocketPhone::Webhook.signature("whsec", sent.body, sent.headers["X-Sendblue-Signature"][/t=(\d+)/, 1]),
      sent.headers["X-Sendblue-Signature"]
  end

  test "an unsigned webhook carries no signature, and an unreachable app is reported" do
    sent = nil
    stub_request(:post, WEBHOOK).with { |request| sent = request }
    PocketPhone::Webhook.deliver(type: "receive", url: WEBHOOK, payload: {})
    refute sent.headers.key?("X-Sendblue-Signature")

    stub_request(:post, WEBHOOK).to_raise(Errno::ECONNREFUSED)
    result = PocketPhone::Webhook.deliver(type: "receive", url: WEBHOOK, payload: {})
    assert_match(/ECONNREFUSED/, result["error"])
  end

  test "a tapback is worded the way an iPhone words it" do
    assert_equal "Laughed at “ha”", PocketPhone::Carrier.reaction_text({ "content" => "ha" }, "laugh")
    assert_equal "Reacted 🔥 to “ha”", PocketPhone::Carrier.reaction_text({ "content" => "ha" }, "🔥")
    assert_equal "Loved an attachment", PocketPhone::Carrier.reaction_text({ "content" => "" }, "love")
  end
end
