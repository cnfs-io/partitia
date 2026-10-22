# frozen_string_literal: true

require "mixlib/shellout"
require "open3"
require_relative "instrumentable"

module Partitia
  module Support
    # The one subprocess boundary for the CNFS family. A thin adapter over the
    # mixlib-shellout gem (Chef/Progress Software) that applies OUR conventions and
    # returns a normalized result. Every gem shells out through here rather than
    # hand-rolling IO.popen/system, so timeout, stdout/stderr/exitstatus separation,
    # secret hygiene, and instrumentation all live in one place.
    #
    #   result = Partitia::Support::Shell.run("git", "status", cwd: repo, timeout: 30)
    #   result.success?   # => true / false (exitstatus.zero?)
    #   result.stdout     # captured stdout (NOT merged with stderr)
    #   result.stderr     # captured stderr (kept distinct)
    #   result.exitstatus # Integer, or nil on timeout
    #
    # Design points (see chorus doc/plans/009):
    # - **Array-argv only.** Pass the command as separate arguments; there is no
    #   shell string to interpolate, so it is injection-safe by construction.
    # - **Non-raising by default.** `run` returns the result even on failure so the
    #   caller decides what to do (record into a Result, retry, ignore). A hung
    #   subprocess (timeout) and a missing binary (ENOENT) are normalized into a
    #   failed result, NOT raised — they are operational, not programmer, errors.
    #   `run!` is the raising variant for callers that want it.
    # - **Instrumented** under `partitia_support.shell.run` (ActiveSupport::Notifications,
    #   via Instrumentable) so a subscriber (partitia-telemetry) turns each subprocess
    #   into a span. The payload carries the command, cwd, exitstatus and success —
    #   never stdout/stderr (unbounded) and never a redacted command's arguments.
    # - **Sensitive-aware.** `sensitive: true` suppresses argument values from both
    #   the instrumentation payload and mixlib's own exception output, for
    #   credential-bearing invocations.
    #
    # ## `run` vs `stream`
    #
    # `run` runs a command to completion and returns its output — right for every
    # one-shot (git, npx, a skill install). `stream` (see below) drives a
    # long-running child that emits output incrementally (e.g. a coding-agent CLI
    # printing NDJSON as it works): it *yields* each stdout line as it arrives,
    # supports an idle (not wall-clock) timeout, and escalates INT->KILL on Ctrl+C
    # while preserving partial output.
    #
    # `run` is backed by mixlib-shellout; `stream` is **not** — it uses
    # `Open3.popen3` directly, because mixlib gives no handle on the child (so no
    # INT/KILL escalation), still blocks until exit (so no acting on early events),
    # and offers only a wall-clock timeout. This is the one deliberate exception to
    # "everything goes through mixlib": the boundary is still one class in one gem,
    # which is what the single-swap-point invariant actually protects.
    class Shell
      include Instrumentable

      # mixlib-shellout's own default; a hung agent/npx no longer blocks forever.
      DEFAULT_TIMEOUT = 600

      # `stream`'s idle timeout: the child is killed if NO output arrives for this
      # long. Deliberately not a wall-clock bound — a correct agent run may run for
      # a long time; only silence signals a hang.
      DEFAULT_IDLE_TIMEOUT = 300

      # Grace given to a child to die on INT before it is sent KILL.
      KILL_GRACE = 3

      # Bytes pulled per `read_nonblock` in the stream loop.
      READ_CHUNK = 4096

      REDACTED = "[FILTERED]"

      # Mixed into the `Interrupt` that `stream` re-raises, so a caller rescuing
      # Ctrl+C can still reach the partial `Result` (`rescue Interrupt => e;
      # e.result`) even though the exception, not the Result, is what propagates.
      module StreamInterrupt
        attr_accessor :result
      end

      # Raised by `run!` when a command fails. Carries the normalized result so the
      # caller can still inspect stdout/stderr/exitstatus off the exception.
      class CommandFailed < StandardError
        attr_reader :result

        def initialize(result)
          @result = result
          super(result.failure_message)
        end
      end

      # Normalized, mixlib-agnostic result. `shellout` is the underlying
      # Mixlib::ShellOut for escape hatches (nil when we synthesized a failure from
      # a timeout or a missing binary, since no command ran to completion).
      Result = Struct.new(:command, :stdout, :stderr, :exitstatus, :shellout, :interrupted,
                          keyword_init: true) do
        def success?
          exitstatus == 0
        end

        def failure?
          !success?
        end

        # `run` never sets this member, so read it as false there; `stream` sets it
        # true only when a run was cut short by Ctrl+C.
        def interrupted
          self[:interrupted] || false
        end

        # A compact, secret-free one-liner for logging/recording into a Result.
        # Uses only the executable name, the exit code, and a trimmed stderr tail.
        def failure_message
          code = exitstatus.nil? ? "timed out" : "exited #{exitstatus}"
          detail = stderr.to_s.strip
          detail = "#{detail[0, 500]}…" if detail.length > 500
          detail.empty? ? "#{command.first} #{code}" : "#{command.first} #{code}: #{detail}"
        end
      end

      class << self
        # Run a command and return a normalized Result. Never raises for an
        # operational failure (non-zero exit, timeout, missing binary).
        #
        #   run("npx", "skills", "add", "x", cwd: dir, timeout: 120, sensitive: true)
        #
        # @param argv [Array<String>] the command and its arguments (array form)
        # @param cwd [String, Pathname, nil] working directory
        # @param timeout [Integer] seconds before the child is terminated
        # @param sensitive [Boolean] suppress argument values from payload/exceptions
        # @param env [Hash, nil] environment overrides (nil values unset the var)
        def run(*argv, cwd: nil, timeout: DEFAULT_TIMEOUT, sensitive: false, env: nil)
          argv = normalize_argv(argv)

          instrument(:run, command: command_for_display(argv, sensitive), cwd: cwd&.to_s) do |payload|
            result = execute(argv, cwd: cwd, timeout: timeout, sensitive: sensitive, env: env)
            payload[:exitstatus] = result.exitstatus
            payload[:success]    = result.success?
            result
          end
        end

        # Raising variant: identical to `run` but raises CommandFailed on failure.
        # Chorus's invocation path uses `run` (records into the Result); this exists
        # for callers that genuinely want a raise.
        def run!(*argv, **opts)
          result = run(*argv, **opts)
          raise CommandFailed, result if result.failure?

          result
        end

        # Run a command and YIELD its stdout lines as they arrive, returning the
        # same normalized Result once drained. For a long-running child that emits
        # output incrementally (a coding-agent CLI streaming NDJSON); see the class
        # docs for why this is popen3-backed rather than mixlib.
        #
        #   result = Shell.stream("claude", "-p", prompt, cwd: dir) do |line|
        #     # called once per stdout line, as it arrives, already chomped
        #   end
        #   result.success?     # exitstatus.zero?
        #   result.stdout       # full accumulated stdout (also seen line-by-line)
        #   result.stderr       # accumulated stderr (drained on its own thread)
        #   result.exitstatus   # Integer, or nil on idle-timeout / interrupt
        #   result.interrupted  # true when cut short by Ctrl+C
        #
        # - **A block is required** — without one, use `run`.
        # - **Idle timeout, not wall-clock.** The child is killed only after
        #   `idle_timeout` seconds of *silence*; each read resets the clock.
        # - **Interrupt (Ctrl+C)** escalates INT then KILL, marks the Result
        #   `interrupted`, then re-raises so the program still stops. The Result is
        #   reachable off the re-raised exception (`rescue Interrupt => e; e.result`).
        # - **Non-raising for operational failures** (non-zero exit, idle timeout,
        #   missing binary), exactly like `run`. There is no `stream!`.
        #
        # @param argv [Array<String>] the command and its arguments (array form)
        # @param cwd [String, Pathname, nil] working directory
        # @param idle_timeout [Integer] seconds of silence before the child is killed
        # @param sensitive [Boolean] suppress argument values from the payload
        # @param env [Hash, nil] environment overrides (nil values unset the var)
        def stream(*argv, cwd: nil, idle_timeout: DEFAULT_IDLE_TIMEOUT, sensitive: false, env: nil)
          raise ArgumentError, "stream requires a block; use `run` for run-to-completion" unless block_given?

          argv = normalize_argv(argv)

          instrument(:stream, command: command_for_display(argv, sensitive), cwd: cwd&.to_s) do |payload|
            lines = 0
            result = stream_exec(argv, cwd: cwd, idle_timeout: idle_timeout, env: env) do |line|
              lines += 1
              yield line
            end
            payload[:exitstatus]  = result.exitstatus
            payload[:success]     = result.success?
            payload[:lines]       = lines
            payload[:interrupted] = result.interrupted
            result
          end
        end

        private

        def execute(argv, cwd:, timeout:, sensitive:, env:)
          opts = { timeout: timeout, sensitive: sensitive }
          opts[:cwd] = cwd.to_s if cwd
          opts[:environment] = env.transform_keys(&:to_s) if env

          shell = Mixlib::ShellOut.new(*argv, opts)
          shell.run_command
          Result.new(command: argv, stdout: shell.stdout, stderr: shell.stderr,
                     exitstatus: shell.exitstatus, shellout: shell)
        rescue Mixlib::ShellOut::CommandTimeout => e
          # A hung subprocess is an operational failure — normalize, don't raise.
          Result.new(command: argv, stdout: "", stderr: e.message, exitstatus: nil, shellout: nil)
        rescue Errno::ENOENT => e
          # Missing binary — operational (the tool isn't installed), 127 by convention.
          Result.new(command: argv, stdout: "", stderr: e.message, exitstatus: 127, shellout: nil)
        end

        # popen3-backed core of `stream`. Yields each complete stdout line (chomped)
        # as it arrives, accumulates full stdout, drains stderr on a separate thread
        # (the classic popen3 deadlock guard), enforces the idle timeout with
        # IO.select + read_nonblock (buffer-free, so select stays truthful), and
        # escalates INT->KILL on idle timeout or interrupt.
        def stream_exec(argv, cwd:, idle_timeout:, env:)
          spawn_env  = (env || {}).transform_keys(&:to_s).transform_values { |v| v&.to_s }
          # Own process group so INT/KILL reaches the whole tree — an agent CLI
          # spawns children of its own, and signalling only the direct child would
          # orphan them (and leave them holding the stderr pipe open).
          spawn_opts = { pgroup: true }
          spawn_opts[:chdir] = cwd.to_s if cwd

          stdout_buf  = +""
          line_buf    = +""
          interrupted = false
          timed_out   = false

          Open3.popen3(spawn_env, *argv, spawn_opts) do |stdin, stdout, stderr, wait_thr|
            stdin.close
            # A child that fills the stderr pipe while we read only stdout would
            # deadlock; drain stderr to EOF on its own thread.
            stderr_drain = Thread.new { stderr.read }

            begin
              catch(:eof) do
                loop do
                  if IO.select([ stdout ], nil, nil, idle_timeout).nil?
                    timed_out = true
                    terminate(wait_thr)
                    throw :eof
                  end

                  begin
                    chunk = stdout.read_nonblock(READ_CHUNK)
                  rescue IO::WaitReadable
                    next # spurious wakeup — re-select
                  rescue EOFError
                    throw :eof # child closed stdout — clean end
                  end

                  stdout_buf << chunk
                  line_buf   << chunk
                  while (idx = line_buf.index("\n"))
                    yield line_buf.slice!(0..idx).chomp
                  end
                end
              end
            rescue Interrupt
              interrupted = true
              terminate(wait_thr)
            end

            # Emit a final newline-less line only on a clean finish (on kill the
            # remainder is a partial fragment; it still rides stdout_buf).
            yield line_buf.chomp if !timed_out && !interrupted && !line_buf.empty?

            stderr_buf = stderr_drain.value.to_s
            exitstatus = timed_out || interrupted ? nil : wait_thr.value.exitstatus

            result = Result.new(command: argv, stdout: stdout_buf, stderr: stderr_buf,
                                exitstatus: exitstatus, shellout: nil, interrupted: interrupted)

            if interrupted
              # Re-raise so Ctrl+C still stops the program, but carry the Result on
              # the exception so a rescuing caller can persist partial work.
              err = Interrupt.new
              err.extend(StreamInterrupt)
              err.result = result
              raise err
            end

            result
          end
        rescue Errno::ENOENT => e
          # Missing binary — operational, 127 by convention (matches `run`).
          Result.new(command: argv, stdout: "", stderr: e.message, exitstatus: 127,
                     shellout: nil, interrupted: false)
        end

        # Escalate INT -> (grace) -> KILL against the child's process group (spawned
        # with pgroup: true, so its pgid equals its pid; the negative target signals
        # the whole tree). `wait_thr` is the Process.detach thread popen3 hands back;
        # #join returns once the group *leader* is reaped.
        #
        # We INT, wait the grace, then KILL the group unconditionally — the leader
        # may die on INT while a child it spawned (an agent's own subprocess) lingers
        # and keeps the stderr pipe open. Once the group is empty the KILL raises
        # ESRCH, which is the benign "already gone" case.
        def terminate(wait_thr)
          Process.kill("INT", -wait_thr.pid)
          wait_thr.join(KILL_GRACE)
          Process.kill("KILL", -wait_thr.pid)
        rescue Errno::ESRCH
          # group already empty — normal, not an error
        end

        # Shared argv discipline for `run` and `stream`, so it cannot drift between
        # them: flatten, stringify, reject empty.
        def normalize_argv(argv)
          argv = argv.flatten.map(&:to_s)
          raise ArgumentError, "no command given" if argv.empty?

          argv
        end

        # The command string put on the instrumentation payload. For a sensitive
        # invocation, only the executable name survives — arguments (which may carry
        # tokens/paths) are collapsed to a single [FILTERED] marker.
        def command_for_display(argv, sensitive)
          return argv.join(" ") unless sensitive
          return argv.first if argv.size == 1

          "#{argv.first} #{REDACTED}"
        end
      end
    end
  end
end
