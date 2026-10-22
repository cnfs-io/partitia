# partitia-dev

Console ergonomics for CNFS Rails apps. `partitia-dev` gives every CNFS gem a shared,
declarative way to contribute Pry/Rails console helpers — model shortcuts, custom
commands, prompt segments, and a project-reset workflow — without any gem touching
Pry directly. Everything it adds is console-only; it stays completely inert in web
and job processes.

## Installation

Add `partitia-dev` as a dependency in your gem's gemspec (or the app's Gemfile):

```ruby
spec.add_dependency "partitia-dev"
```

Require it before you register anything (do this in your engine, so ordering is
deterministic):

```ruby
# lib/my_gem/engine.rb
require "partitia/dev"
```

## Registering from a gem

A gem contributes console features through a single `Partitia::Dev.console` block. Call
it from the engine's `console` block so it only runs in a console session:

```ruby
# lib/my_gem/engine.rb
module MyGem
  class Engine < ::Rails::Engine
    console do
      require "my_gem/pry_console"
      MyGem::PryConsole.install!
    end
  end
end
```

```ruby
# lib/my_gem/pry_console.rb
module MyGem
  module PryConsole
    module_function

    def install!
      return unless defined?(Partitia::Dev)

      Partitia::Dev.console do |c|
        c.namespace MyGem, "m"
        c.command(:hello) { puts "hi" }
        c.prompt_segment(color: :blue) { current_context }
        c.before_reset { cleanup_tmp }
        c.reset_task "my_gem:sync"
      end
    end
  end
end
```

Any number of gems may call `Partitia::Dev.console`; each call appends. The block yields
a builder `c` supporting the contribution kinds below.

---

## Features

### Model shortcuts

`c.namespace(module, letter)` registers a model namespace and a one-letter prefix.
At console start, every `ActiveRecord` model directly under that namespace is
auto-discovered and given a family of shortcuts. You declare the namespace once —
no per-model configuration.

```ruby
c.namespace Partitia::Okf, "o"    # discovers Partitia::Okf::Bundle, ::Concept, ::ViewPort, ...
c.namespace Chorus,  "c"    # discovers Chorus::Agent, ::AgentProfile, ...
```

Each model gets a shortcut **code** of the form `<letter><model-code>`, e.g.
`Partitia::Okf::Bundle` → `ob`. Every code exposes this family (shown for `ob`):

| Shortcut | Returns |
|----------|---------|
| `ob`     | the class itself (`Partitia::Okf::Bundle`) |
| `oba`    | `.all` |
| `obc`    | `.create(attrs = {})` |
| `obf`    | `.find(id)`, or `.first` when called with no id |
| `obl`    | `.last` |
| `obp`    | `.all.pluck(*args)` — e.g. `obp :name, :age` |

```ruby
ob            # => Partitia::Okf::Bundle
oba           # => Partitia::Okf::Bundle.all
obc name: "x" # => creates and returns a Bundle
obf 3         # => Partitia::Okf::Bundle.find(3)
obl           # => Partitia::Okf::Bundle.last
obp :name     # => Partitia::Okf::Bundle.all.pluck(:name)
```

`obf` and `obl` **memoize** — repeat calls return the same object without
re-querying. Append `!` to force a refresh: `obf! 3`, `obl!`. `obc` automatically
busts the `obl` memo on a successful create.

**Prefix collisions** are resolved automatically. Two gems may register the same
letter; codes lengthen until unique. Within a namespace, models are assigned in
alphabetical order — first claim wins, later ones extend:

```
Chorus::Agent        => ca
Chorus::AgentProfile => cap
Chorus::Artifact     => car     # "ca" taken, extends
Chorus::Skill        => cs
Chorus::Source       => cso     # "cs" taken, extends
```

Only models **directly** under the namespace are discovered; nested ones
(`Chorus::Source::Git`) are skipped.

#### Top-level models — `c.model`

Models that live outside any gem namespace (a top-level `Tenant`, `Account`, ...)
can't be reached by `c.namespace`. Register them individually with
`c.model(klass, letter)`; the code is derived from the class name the same way and
shares the same collision handling.

```ruby
c.model(Tenant, "t")    # => tt, tta, ttc, ttf, ttl, ttp
c.model(Account, "a")   # => aa, aaa, aac, aaf, aal, aap
```

#### `shortcuts` — list what's registered

```ruby
shortcuts       # print every shortcut family
shortcuts "c"   # only families whose code starts with "c"
shortcuts "ca"  # only families whose code starts with "ca"
```

#### `clear!` — drop memoized records

```ruby
clear!        # clear all memos
clear! :obf   # clear memos for one family
```

Memos are also cleared automatically whenever you `reload!`.

---

### Custom commands

`c.command(name) { ... }` defines a bare console helper. The block becomes a
method on the console; arguments pass straight through.

```ruby
c.command(:vst) { |name = ""| ApplicationRecord.current_tenant = name }
```

```ruby
vst "acme"   # at the console
```

---

### Prompt segments

`c.prompt_segment(color:) { ... }` adds a bracketed segment to the console prompt,
after the built-in Rails-env segment. The block runs at render time; return the
text to show, or `nil`/`""` to render nothing.

```ruby
c.prompt_segment(color: :blue) do
  t = ApplicationRecord.current_tenant rescue nil
  t.to_s.empty? ? nil : t
end
```

Renders e.g. `[development][acme] cnfs(main)>`.

Available colors: `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`,
`:grey`/`:gray`. Omit `color:` for uncolored text.

---

### Project reset

`reset_project!` re-runs `db:reset` + `db:seed` from inside the console (no need to
exit), and can be extended by gems.

```ruby
reset_project!   # at the console
```

Gems extend the reset in two ways:

```ruby
c.before_reset { FileUtils.rm_rf(Rails.root.join("tmp/bundles")) }  # run before each reset
c.reset_task "okf:sync"                                             # append a rake task to the chain
```

`before_reset` blocks run first (in registration order), then `db:reset`,
`db:seed`, and any registered `reset_task`s in order. Memos are cleared as part of
the reset.

---

## Built-in console helpers

Available at the prompt without any registration:

| Helper | Does |
|--------|------|
| `r`    | reload app code (alias for Rails' `reload!`) |
| `reload!` | reloads and clears all shortcut memos |
| `shortcuts [match]` | list registered model shortcut families |
| `clear! [name]` | clear memoized records |
| `reset_project!` | re-run db:reset + db:seed (plus registered tasks) |

## Step aliases (with pry-byebug)

`pry-byebug` loads with the console wiring (`rails console`), not when the gem is
required, so web and job processes never load it. In the console these debugger
aliases are installed: `n` (next), `s` (step), `c` (continue), `f` (finish).

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
