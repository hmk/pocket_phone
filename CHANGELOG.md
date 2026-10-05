# Changelog

## 0.1.1

- Fix every API call failing with `uninitialized constant` in an app that
  declares `inflect.acronym "API"`. The API controller is now
  `PocketPhone::SendblueController`; no URL changes.

## 0.1.0

First version.

- A fake Sendblue API: messages, group messages, carousels, typing indicators,
  tapbacks, read receipts, service lookup, media upload, contact sharing and
  message history.
- An iMessage-style inbox for the phones on the other end, with blue and green
  bubbles, attachments, group chats and link previews.
- Signed `receive` webhooks for what the phones send, plus status callbacks,
  outbound webhooks and typing webhooks.
- Per-person simulation of Android phones, failed sends and refused sends.
