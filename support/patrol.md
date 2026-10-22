# patrol.md — cnfs_support

Append-only, newest entry on top. Written by `docs-patrol` / `docs-sheriff`.
Baseline entry = the onboarding checkpoint the next patrol measures drift against.

## 2026-07-09 — sheriff (onboarding baseline)
run: session 8817a3f4-553a-453e-8249-4f03c9e02b83 · cwd /Users/robertroach/spikes/chorus/gems/support
commit: 9b1812f807d73380afe56ddd985387c8ebb533b1

verdict: coherent (baseline — docs reconciled during this onboarding)
drift score: 0

### onboarding actions taken
- Authored `CLAUDE.md` `#coherence` (`level: project`): two `[critical]` boundary
  claims (no runtime Rails dep; no runtime OTel dep), four `[high]`
  identity/structure claims (unified component-tag; Instrumentable emits
  notifications and creates no spans; Logging is an independent per-tag layer, not
  a TaggedLogging wrapper; Railtie injects `instrument` into records but not
  controllers), one `[high]` + one `[medium]` config/redaction claim, one
  `[medium]` docs↔plans claim, and one redaction-consumption flux entry
  (tracking plan 008).
- Reconciled `README.md`: three stale tag/level-key strings said `okf` where the
  live `component_tag` (asserted by green specs) yields `cnfs_okf` —
  `Okf::Button → cnfs_okf`, "tag `cnfs_okf`", and `levels["cnfs_okf"]`. Fixed.
- Registered `support` in the area roster (`gems/CLAUDE.md` `#coherence`) so
  patrol fans out to it.
- No gem-local `doc/plans` exist (build is space-driven via `../../doc/plans`);
  nothing to retire.

### code bugs — STOP (flagged, NOT fixed — needs a human)
- `CnfsSupport.component_tag` (`lib/cnfs_support.rb:20`) raises `NoMethodError`
  (`undefined method 'underscore' for nil`) when given `nil` or `""`:
  `"".split("::").first` is `nil`, and `.underscore` is called on it with no
  guard. The method's own doc-comment (and the commented-out prior implementation
  just below it) promises nameless/anonymous classes fall back to `"cnfs"` — the
  current code does not. Reachable when an **anonymous** class
  (`Class.new { include CnfsSupport::Logging }`, `self.class.name == nil`) calls
  `logger` or `instrument`. Note `Instrumentable.event_name` *does* guard the
  analogous empty case (`subject = "object" if subject.empty?`), so the missing
  guard in `component_tag` reads as an oversight, not a deliberate contract.
  Sheriff does not touch code; flag for a human. Fix is either restore the
  empty→`"cnfs"` fallback or document anonymous classes as unsupported.

### docs ↔ code comment (proposed, NOT applied — source file)
- `lib/cnfs_support.rb:13-25`: the `component_tag` doc-comment still describes the
  removed behavior (`"Okf::Button" => "okf"`, fallback `"cnfs"`) and the old
  implementation sits commented-out at lines 21-22. Reality (green specs) is the
  cnfs-prefixed rule (`=> "cnfs_okf"`). Proposed: update the comment to the
  cnfs-prefix rule and delete the dead commented lines. Not applied here because
  it edits a source file — left for a human to sweep with the bug fix above.

### state (context, not scored)
- uncommitted: 5 — `CLAUDE.md` (new, this onboarding), `README.md` (reconciled),
  `patrol.md` (this file, once saved), plus pre-existing untracked
  `lib/cnfs_support/redaction_config.rb` + `spec/cnfs_support/redaction_config_spec.rb`
  (plan 006 WS3, shipped-but-uncommitted). `Gemfile.lock` also modified: `bundle
  install` fetched the `opentelemetry-sdk`/`-common`/`-registry` dev/test gems
  that were missing locally so the suite could boot — an environment artifact, not
  a charter change (they remain dev-only; no runtime OTel dep added).
- branched: no (on trunk `main`)
- suite: green — `bundle exec rspec` → 36 examples, 0 failures
- flux: 1 open — redaction consumption (tracking `../../doc/plans/008`)

### notes
- The redaction surface (`RedactionConfig`) is shipped and green but still
  untracked in git and not yet consumed — both facts are captured (flux entry +
  uncommitted state), so this baseline reads as coherent-but-in-motion, not
  drifted. Committing those two files would clear most of the uncommitted state.
