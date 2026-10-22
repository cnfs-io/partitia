require "spec_helper"

RSpec.describe CnfsSupport::Shell do
  describe ".run" do
    it "returns a success result for a zero-exit command" do
      result = described_class.run("true")

      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.exitstatus).to eq(0)
    end

    it "returns a failure result for a non-zero-exit command (does NOT raise)" do
      result = described_class.run("false")

      expect(result).to be_failure
      expect(result.exitstatus).to eq(1)
    end

    it "captures stdout" do
      result = described_class.run("echo", "hello world")

      expect(result.stdout.strip).to eq("hello world")
      expect(result.stderr).to eq("")
    end

    it "keeps stdout and stderr distinct (not merged)" do
      result = described_class.run("sh", "-c", "echo out; echo err 1>&2; exit 4")

      expect(result.stdout.strip).to eq("out")
      expect(result.stderr.strip).to eq("err")
      expect(result.exitstatus).to eq(4)
      expect(result).to be_failure
    end

    it "passes arguments as an array with no shell interpolation" do
      # If this went through a shell, $(…) would execute; array form keeps it literal.
      result = described_class.run("echo", "$(echo pwned)")

      expect(result.stdout.strip).to eq("$(echo pwned)")
    end

    it "runs in the given cwd" do
      result = described_class.run("pwd", cwd: "/tmp")

      expect(result.stdout.strip).to eq(File.realpath("/tmp"))
    end

    it "injects environment overrides" do
      result = described_class.run("sh", "-c", "echo $CNFS_SHELL_TEST", env: { "CNFS_SHELL_TEST" => "xyz" })

      expect(result.stdout.strip).to eq("xyz")
    end

    it "normalizes a timeout into a failure result rather than raising" do
      result = described_class.run("sleep", "5", timeout: 1)

      expect(result).to be_failure
      expect(result.exitstatus).to be_nil
      expect(result.failure_message).to match(/timed out/)
    end

    it "normalizes a missing binary into a failure result (127) rather than raising" do
      result = described_class.run("cnfs_no_such_binary_xyz")

      expect(result).to be_failure
      expect(result.exitstatus).to eq(127)
    end

    it "raises ArgumentError when no command is given" do
      expect { described_class.run }.to raise_error(ArgumentError)
    end

    it "exposes the underlying Mixlib::ShellOut for escape hatches" do
      result = described_class.run("true")

      expect(result.shellout).to be_a(Mixlib::ShellOut)
    end
  end

  describe ".run instrumentation" do
    it "emits cnfs_support.shell.run with a secret-free payload" do
      payload = nil
      sub = ActiveSupport::Notifications.subscribe("cnfs_support.shell.run") { |*, pl| payload = pl }

      described_class.run("echo", "hi", cwd: "/tmp")

      expect(payload[:command]).to eq("echo hi")
      expect(payload[:cwd]).to eq("/tmp")
      expect(payload[:exitstatus]).to eq(0)
      expect(payload[:success]).to be(true)
      # stdout/stderr are unbounded blobs — they must never ride the payload.
      expect(payload).not_to have_key(:stdout)
      expect(payload).not_to have_key(:stderr)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "redacts arguments from the payload when sensitive" do
      payload = nil
      sub = ActiveSupport::Notifications.subscribe("cnfs_support.shell.run") { |*, pl| payload = pl }

      described_class.run("echo", "s3cr3t-token", sensitive: true)

      expect(payload[:command]).to eq("echo [FILTERED]")
      expect(payload[:command]).not_to include("s3cr3t-token")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
  end

  describe ".run!" do
    it "returns the result on success" do
      expect(described_class.run!("true")).to be_success
    end

    it "raises CommandFailed on failure, carrying the result" do
      expect { described_class.run!("false") }.to raise_error(described_class::CommandFailed) do |error|
        expect(error.result.exitstatus).to eq(1)
      end
    end
  end

  describe ".stream" do
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    it "yields each line of a multi-line output, in order, chomped" do
      lines = []
      result = described_class.stream("printf", "a\nb\nc\n") { |line| lines << line }

      expect(lines).to eq(%w[a b c])
      expect(result).to be_success
    end

    it "yields lines incrementally, before the process exits" do
      timings = []
      described_class.stream("sh", "-c", "echo first; sleep 1; echo second") do |line|
        timings << [ line, now ]
      end

      expect(timings.map(&:first)).to eq(%w[first second])
      # The first line must have been delivered before the sleep completed.
      expect(timings[1][1] - timings[0][1]).to be >= 0.5
    end

    it "accumulates full stdout on the Result alongside yielding" do
      result = described_class.stream("printf", "x\ny\n") { |_| }

      expect(result.stdout).to eq("x\ny\n")
    end

    it "keeps stderr distinct and does not deadlock on a heavy stderr writer" do
      out = []
      result = described_class.stream("sh", "-c", "seq 1 20000 1>&2; echo done") { |line| out << line }

      expect(out).to eq(%w[done])
      expect(result.stderr.lines.count).to eq(20_000)
      expect(result).to be_success
    end

    it "returns a failure result for a non-zero exit (does NOT raise)" do
      result = described_class.stream("sh", "-c", "echo hi; exit 3") { |_| }

      expect(result).to be_failure
      expect(result.exitstatus).to eq(3)
    end

    it "fires the idle timeout on a silent child" do
      started = now
      result = described_class.stream("sleep", "5", idle_timeout: 1) { |_| }

      expect(result).to be_failure
      expect(result.exitstatus).to be_nil
      expect(result.failure_message).to match(/timed out/)
      expect(now - started).to be < 4 # killed, not waited out
    end

    it "does NOT fire the idle timeout on a chatty long-running child" do
      lines = []
      result = described_class.stream(
        "sh", "-c", "for i in 1 2 3 4 5 6 7 8 9 10; do echo $i; sleep 0.2; done", idle_timeout: 1
      ) { |line| lines << line }

      expect(result).to be_success
      expect(lines).to eq(%w[1 2 3 4 5 6 7 8 9 10])
    end

    it "normalizes a missing binary into a failure result (127)" do
      result = described_class.stream("cnfs_no_such_binary_xyz") { |_| }

      expect(result).to be_failure
      expect(result.exitstatus).to eq(127)
    end

    it "raises ArgumentError when no block is given" do
      expect { described_class.stream("true") }.to raise_error(ArgumentError)
    end

    it "passes arguments as an array with no shell interpolation" do
      lines = []
      described_class.stream("echo", "$(echo pwned)") { |line| lines << line }

      expect(lines).to eq([ "$(echo pwned)" ])
    end

    it "runs in the given cwd" do
      lines = []
      described_class.stream("pwd", cwd: "/tmp") { |line| lines << line }

      expect(lines.first).to eq(File.realpath("/tmp"))
    end

    it "injects environment overrides" do
      lines = []
      described_class.stream("sh", "-c", "echo $CNFS_SHELL_TEST", env: { "CNFS_SHELL_TEST" => "xyz" }) do |line|
        lines << line
      end

      expect(lines).to eq(%w[xyz])
    end

    describe "interrupt handling" do
      it "reaps the child, marks the Result interrupted with partial stdout, and re-raises" do
        lines = []
        raised = nil
        result = nil
        started = now

        begin
          described_class.stream("sh", "-c", "echo one; echo two; sleep 5") do |line|
            lines << line
            raise Interrupt if lines.size == 1
          end
        rescue Interrupt => e
          raised = e
          result = e.result if e.respond_to?(:result)
        end

        expect(raised).to be_a(Interrupt)
        expect(now - started).to be < 4 # child killed, not left to sleep 5
        expect(lines).to eq(%w[one])
        expect(result).not_to be_nil
        expect(result.interrupted).to be(true)
        expect(result.stdout).to include("one")
      end
    end
  end

  describe ".stream instrumentation" do
    it "emits cnfs_support.shell.stream with a secret-free payload" do
      payload = nil
      sub = ActiveSupport::Notifications.subscribe("cnfs_support.shell.stream") { |*, pl| payload = pl }

      described_class.stream("printf", "a\nb\n", cwd: "/tmp") { |_| }

      expect(payload[:lines]).to eq(2)
      expect(payload[:success]).to be(true)
      expect(payload[:exitstatus]).to eq(0)
      expect(payload[:interrupted]).to be(false)
      expect(payload[:cwd]).to eq("/tmp")
      # stdout/stderr are unbounded blobs — they must never ride the payload.
      expect(payload).not_to have_key(:stdout)
      expect(payload).not_to have_key(:stderr)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "redacts arguments from the payload when sensitive" do
      payload = nil
      sub = ActiveSupport::Notifications.subscribe("cnfs_support.shell.stream") { |*, pl| payload = pl }

      described_class.stream("echo", "s3cr3t-token", sensitive: true) { |_| }

      expect(payload[:command]).to eq("echo [FILTERED]")
      expect(payload[:command]).not_to include("s3cr3t-token")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
  end
end
