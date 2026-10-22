# Chatter Engine — Vanilla Chat Implementation Plan (Milestone 1)

This document is the implementation brief for Claude Code (CC). It describes the
first vanilla milestone of the `chatter` mountable Rails engine: **direct (DM) and
group conversations with real-time message delivery via Turbo Streams**, tested
through the bundled dummy app.

Build idiomatically. Do not code defensively around anticipated bugs — if something
breaks (e.g. at migrate time), stop and report it so we can diagnose empirically.

---

## 0. Context & environment (already in place — do not change)

- Rails **8.1.3**, Ruby (arm64-darwin), mountable engine `Chatter`, `isolate_namespace Chatter`.
- **Importmap** (not jsbundling/esbuild). Ship JS via the engine importmap and pin it. Do **not** introduce npm/node/esbuild.
- **Propshaft** asset pipeline. **Tailwind 4** (`tailwindcss-rails`). Generators templated to `:tailwindcss`.
- **turbo-rails 2.0.23**, **stimulus-rails** present.
- **RSpec** (`rspec-rails`) + **FactoryBot** are the test stack. No Minitest specs.
- Dummy app at `spec/dummy`, engine mounted at `/chatter`.
- Cable adapter: `async` in development, `test` in test. **Do not add Redis.**
- ActiveRecord is loaded in the dummy but **no schema/migrations exist yet**.
- Dummy has `config.action_controller.include_all_helpers = false` — engine controllers/views must wire their own helpers.
- ActionText/Trix is available as a dependency but is **NOT used in this milestone** (see §7).

---

## 1. Architectural principles (read before writing code)

### 1.1 The engine owns conversations; the host owns identity
The engine knows about **participants**, never about authentication. The engine must
**never reference a `User` (or `Person`, or `Agent`) constant directly**. It talks to
participants only through a polymorphic association and a concern the host mixes in.

### 1.2 Participants are polymorphic and heterogeneous
A participant is anything that can be in a conversation and send messages. In the dummy
that is two unrelated host models — `Person` (human) and `Agent` (non-human) — both of
which `include Chatter::Participant`. The engine sees only a polymorphic `participant`
and must work identically regardless of concrete type. This heterogeneity is the whole
point: it proves the seam that will later let an LGAT support agent drop in as just
another participant.

### 1.3 A DM is not a special type — it is a shape
Model one generic `Conversation` with members. A **direct** conversation has exactly two
participants; a **group** has a name and any number. Use a `kind` enum to distinguish,
but keep one model and one code path. Do not build separate DM and Group classes.

### 1.4 Polymorphic associations have no foreign key (by design)
- `Membership#participant` → `t.references :participant, polymorphic: true` (no FK; creates `participant_type`/`participant_id`).
- `Message#sender` → `t.references :sender, polymorphic: true` (no FK).
- The only real FK is `conversation` on memberships and messages → `chatter_conversations`.
Write these the normal idiomatic way (`foreign_key: true` only on the `conversation` refs).

---

## 2. Schema (engine migrations)

Create migrations under the engine's `db/migrate`. All tables are namespaced
`chatter_*` automatically because the models live under `Chatter::`.

### `chatter_conversations`
| column      | type     | notes                                            |
|-------------|----------|--------------------------------------------------|
| `kind`      | integer  | enum: `direct: 0`, `group: 1`, null: false, default 0 |
| `name`      | string   | nullable (used for groups; null for DMs)         |
| timestamps  |          |                                                  |

### `chatter_memberships`
| column             | type     | notes                                                  |
|--------------------|----------|--------------------------------------------------------|
| `conversation`     | refs     | `foreign_key: true`, null: false → chatter_conversations |
| `participant`      | refs     | `polymorphic: true`, null: false (no FK)               |
| `role`             | integer  | enum: `member: 0`, `owner: 1`, null: false, default 0  |
| `last_read_at`     | datetime | nullable (reserved for a later read-receipts milestone; add the column now, leave unused) |
| timestamps         |          |                                                        |

Add a unique index on `[conversation_id, participant_type, participant_id]` to prevent
duplicate memberships.

### `chatter_messages`
| column          | type     | notes                                                |
|-----------------|----------|------------------------------------------------------|
| `conversation`  | refs     | `foreign_key: true`, null: false → chatter_conversations |
| `sender`        | refs     | `polymorphic: true`, null: false (no FK)             |
| `content`       | text     | null: false (plain text for this milestone)          |
| timestamps      |          |                                                      |

Index `[conversation_id, created_at]` for ordered retrieval.

### Install into the dummy
After creating engine migrations:
1. `cd spec/dummy`
2. `bin/rails chatter:install:migrations`
3. `bin/rails db:prepare` (or `db:create db:migrate`)

If migration fails, **stop and report the exact error** — do not invent workarounds.

---

## 3. Models

### `Chatter::Participant` concern (`app/models/concerns/chatter/participant.rb`)
The seam the host mixes into its participant models. Provides:
- `has_many :memberships, as: :participant, class_name: "Chatter::Membership"`
- `has_many :conversations, through: :memberships, class_name: "Chatter::Conversation"`
- `has_many :sent_messages, as: :sender, class_name: "Chatter::Message"`
- A `chatter_display_name` method with a sensible default the host can override (used in views so the engine never assumes the host's name attribute). Default to something safe; let host models override.

### `Chatter::Conversation` (`app/models/chatter/conversation.rb`)
- `enum :kind, { direct: 0, group: 1 }`
- `has_many :memberships, dependent: :destroy`
- `has_many :messages, dependent: :destroy`
- `has_many :participants` via memberships is awkward across polymorphic types — expose `memberships` and read `membership.participant` rather than a `through` of mixed classes.
- Validation: a `direct` conversation must have exactly 2 memberships; a `group` should have a `name`. (Membership-count validation may run on a callback/after save; keep it pragmatic.)
- Turbo: `broadcasts_to ->(conversation) { conversation }` is NOT used at the conversation level; messages broadcast (see below). Keep conversation broadcasting out for now.
- Helper scopes: a class method to find-or-create a direct conversation between two participants (look up an existing `direct` conversation whose two memberships match the pair, else create). This is the DM entry point.

### `Chatter::Membership` (`app/models/chatter/membership.rb`)
- `belongs_to :conversation`
- `belongs_to :participant, polymorphic: true`
- `enum :role, { member: 0, owner: 1 }`
- Validations: uniqueness of participant within a conversation.

### `Chatter::Message` (`app/models/chatter/message.rb`)
- `belongs_to :conversation`
- `belongs_to :sender, polymorphic: true`
- `validates :content, presence: true`
- **Real-time:** `broadcasts_to ->(message) { message.conversation }, inserts_by: :append, target: ->(message) { "conversation_#{message.conversation_id}_messages" }`
  - Keep the broadcast partial as `chatter/messages/message` so the upgrade to ActionText later (see §7) is localized to that partial + the form.
- Default scope or explicit `order(:created_at)` when listing.

---

## 4. Controllers & routes

### Engine routes (`config/routes.rb`)
```ruby
Chatter::Engine.routes.draw do
  resources :conversations, only: [:index, :show, :create] do
    resources :messages, only: [:create]
  end
  # DM convenience: POST to start/find a direct conversation with a participant
  # Keep RESTful; a conversations#create with kind param is fine.
  root to: "conversations#index"
end
```

### `Chatter::ConversationsController`
- `index` — conversations the `current_participant` belongs to (via their memberships), split/orderable into DMs and groups in the view.
- `show` — the conversation with its messages; renders the message list + the form + subscribes to the Turbo Stream (`turbo_stream_from "conversation_#{@conversation.id}_messages"`). Authorize: current participant must be a member.
- `create` — create a group (with name + initial member ids) OR find-or-create a direct conversation with another participant, based on `kind`.

### `Chatter::MessagesController`
- `create` — build message with `sender: current_participant`, save, rely on `broadcasts_to` for delivery to all subscribers. Respond with a Turbo Stream that appends to the sender's own stream (or rely solely on the broadcast — pick the simplest correct path; broadcasting to the stream the sender is also subscribed to means the sender sees their own message via the same broadcast, which is fine).

### `current_participant` seam (parent_controller convention)
The engine needs to know who is acting, but must not contain auth. Use the standard
mountable-engine convention (as in Devise, Spree, turbo-rails): the engine's
`ApplicationController` **inherits from a host-configurable parent controller**, and
declares `current_participant` as a method the host is expected to provide. No global
proc, no resolver indirection, no load-order surprises beyond the well-understood
parent_controller pattern — the dependency is named in the controller where it is
discoverable, and the host satisfies it through normal inheritance.

`lib/chatter.rb` — a single config point with a safe standalone default:
```ruby
module Chatter
  mattr_accessor :parent_controller, default: "ActionController::Base"
end
```

`app/controllers/chatter/application_controller.rb`:
```ruby
module Chatter
  class ApplicationController < Chatter.parent_controller.constantize
    private

    def current_participant
      raise NotImplementedError,
        "The host app must provide `current_participant` returning a Chatter participant. " \
        "Set Chatter.parent_controller to your host's base controller (which defines it), " \
        "or define current_participant in this controller."
    end
    helper_method :current_participant
  end
end
```

Notes for CC:
- `Chatter.parent_controller.constantize` is evaluated at class-definition time, so the
  host must set `Chatter.parent_controller` in an initializer that runs **before** the
  engine's controllers load. This is the normal pattern (turbo-rails does exactly this).
  If you hit a genuine load-order problem, report it rather than working around it.
- When the host's base controller already defines `current_participant` (or aliases it to
  its existing `current_user`/`current_person`), the engine inherits it and the
  `NotImplementedError` is never reached. That is the "include without refactoring" goal:
  the LGAT admin app already has an authenticated current user; it just exposes it as
  `current_participant`.
- Do **not** hardcode any host model (`Person`/`Agent`) anywhere in the engine.

---

## 5. Dummy app: host responsibilities

The dummy plays the role of the enclosing application. It provides identity, the
participant models, fake auth, and the switcher — wired exactly the way the LGAT admin
app will wire it, so the dummy doubles as the reference integration.

### Models (generated in `spec/dummy`)
- `Person` — `name:string`; `include Chatter::Participant`; override `chatter_display_name` to return `name`.
- `Agent` — `name:string` (+ maybe `kind:string` later); `include Chatter::Participant`; override `chatter_display_name`.
- Generate migrations for both, migrate into the dummy DB.

### Fake auth + switcher
- Session holds `current_participant_gid` (a GlobalID string so it can reference either a `Person` or an `Agent`).
- The dummy's own `ApplicationController` (`spec/dummy/app/controllers/application_controller.rb`) defines `current_participant`, resolving the session GlobalID to a record:
  ```ruby
  class ApplicationController < ActionController::Base
    def current_participant
      gid = session[:current_participant_gid]
      GlobalID::Locator.locate(gid) if gid
    end
    helper_method :current_participant
  end
  ```
- Wire the engine to inherit from it, in `spec/dummy/config/initializers/chatter.rb`:
  ```ruby
  Chatter.parent_controller = "::ApplicationController"
  ```
  Because the engine's `Chatter::ApplicationController` then inherits from the dummy's
  base controller, it picks up `current_participant` automatically — the engine's
  `NotImplementedError` default is never hit. This is the exact contract LGAT admin will
  satisfy.
- A **switcher**: a small bar (partial in the dummy layout) listing all Persons and Agents
  as links that set `session[:current_participant_gid]` and redirect back. The session-set
  action lives in the **dummy** (a tiny dummy controller/route), not the engine. This lets
  you open two browser tabs / a normal + incognito window, "become" different participants,
  and watch real-time delivery.
- Seed a handful of Persons and an Agent in `db/seeds.rb`.

### Routes
Dummy root → redirect into `/chatter` (or render the switcher + link in). Add the small
switcher route(s) in the dummy. Keep it minimal; the engine owns the real screens.

---

## 6. Views & assets

- Engine views under `app/views/chatter/`, styled with Tailwind 4 utility classes. Keep them clean and legible, not elaborate — this is a functional spike.
- Key partials:
  - `conversations/index` — list of DMs and groups for current participant.
  - `conversations/show` — header, `turbo_stream_from`, `#conversation_<id>_messages` container rendering `messages/message`, and the new-message form.
  - `messages/_message` — single message bubble showing `sender.chatter_display_name` + `content`. **Isolate all body rendering here** (ActionText upgrade later touches only this + the form).
  - `messages/_form` — `form_with model: [conversation, Chatter::Message.new]`, a text field + submit.
- Stimulus: only if needed (e.g. auto-scroll to bottom on new message, reset form after submit). If added, pin via the engine importmap. Keep JS minimal.
- Helpers: because the dummy sets `include_all_helpers = false`, ensure engine controllers expose needed helpers explicitly.

---

## 7. Deliberately deferred (do NOT build in this milestone)

- **ActionText/Trix rich bodies** — phase 2. Structure the message partial + form so the swap is localized. (Upgrade buys: formatting, ActiveStorage attachments, sanitization, mention/embed hook.)
- **Invites / membership management UI** — later milestone (`last_read_at` column is pre-added but unused).
- **Read receipts / unread counts** — later milestone.
- **The LGAT support agent behavior** — separate effort; it will arrive as a participant.

---

## 8. Tests (RSpec + FactoryBot)

Write specs as you build, not at the end:
- **Factories**: `Chatter::Conversation`, `Chatter::Membership`, `Chatter::Message`, plus dummy `Person` and `Agent`.
- **Model specs**: participant concern associations work for both Person and Agent; direct-conversation find-or-create; membership uniqueness; direct-vs-group validations.
- **Request specs**: a member can view a conversation; a non-member cannot; creating a message persists it.
- **Broadcast**: assert a message create broadcasts a Turbo Stream to the conversation stream (`have_broadcasted_to` with the turbo-rails test helpers, `test` cable adapter).

---

## 9. Suggested build order

1. Engine migrations → install into dummy → migrate. **Confirm DB is clean before proceeding.**
2. `Chatter::Participant` concern + the three engine models + factories. Model specs green.
3. Dummy `Person` + `Agent` models including the concern; seeds; the dummy `current_participant` + `parent_controller` initializer; the switcher.
4. Conversations controller + index/show views; group + DM creation. Static (non-real-time) message listing working.
5. Messages controller + form + `broadcasts_to`. Real-time delivery working across two tabs.
6. Request + broadcast specs green. Polish Tailwind styling last.

At each numbered step, run the dummy (`bin/dev` or `bin/rails s` from `spec/dummy`) and the spec suite before moving on.

---

## 10. Open seams noted for the future (no action now)

- The two host-facing configuration points are: `Chatter.parent_controller` (host base
  controller providing `current_participant`) and `chatter_display_name` (overridden in
  participant models). When porting to the LGAT platform, those plus
  `include Chatter::Participant` are the entire host contract.
- The find-or-create direct-conversation logic is where blocking/privacy rules would later hook in.
