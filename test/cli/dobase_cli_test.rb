# frozen_string_literal: true

require "test_helper"
require "open3"
require "shellwords"
require "tmpdir"

# The CLI is a separate program talking HTTP; these tests cover what can be
# checked without a server: that every command file loads, the help, and the
# input helpers commands rely on.
class DobaseCliTest < ActiveSupport::TestCase
  CLI = Rails.root.join("cli/dobase").to_s

  setup do
    $LOAD_PATH.unshift Rails.root.join("cli/lib").to_s unless $LOAD_PATH.include?(Rails.root.join("cli/lib").to_s)
    require "dobase/cli"
  end

  test "help lists every command and exits cleanly" do
    output, status = run_cli("help")

    assert status.success?
    Dobase::Command::DEFINITIONS.each_key { |name| assert_includes output, "dobase #{name}" }
  end

  test "noun help shows flags" do
    output, status = run_cli("help", "card")

    assert status.success?
    assert_includes output, "--assignee USER"
  end

  test "unknown commands exit with a usage error" do
    _output, status, errors = run_cli("frobnicate")

    assert_equal 2, status.exitstatus
    assert_includes errors, "Unknown command"
  end

  test "commands need a saved login or environment" do
    _output, status, errors = run_cli("whoami")

    assert_equal 1, status.exitstatus
    assert_includes errors, "Not signed in"
  end

  test "every command has a summary and well-formed arguments" do
    Dobase::Command::DEFINITIONS.each_value do |definition|
      assert definition.summary.present?, "#{definition.name} has no summary"
      assert definition.args.all? { |arg| arg.match?(/\A\[?[A-Z\/]+(\.\.\.)?\]?\z/) }, "#{definition.name} has odd args: #{definition.args}"
      assert Dobase::Command::NOUNS.key?(definition.name.split.first) || !definition.name.include?(" "), "#{definition.name} has no noun summary"
    end
  end

  test "the skill and readmes only show commands and flags that exist" do
    examples = {
      "cli/SKILL.md" => /^\$D (.+)$/,
      "cli/README.md" => /^dobase (.+)$/,
      "README.md" => /^dobase (.+)$/
    }.flat_map do |file, pattern|
      Rails.root.join(file).read.scan(pattern).flatten.map { |line| [ file, line ] }
    end
    assert examples.size > 20

    examples.each do |file, line|
      words = Shellwords.split(line.sub(/\s+#.*\z/, "").sub(/<<'\w+'\z/, ""))
      next if words.first == "help"

      definition = Dobase::Command::DEFINITIONS[words.first(2).join(" ")] || Dobase::Command::DEFINITIONS[words.first]
      assert definition, "#{file}: unknown command in `#{line}`"

      words.grep(/\A--[a-z]/).each do |flag|
        name = flag.delete_prefix("--").tr("-", "_").to_sym
        assert definition.flags.key?(name) || name == :json, "#{file}: `#{definition.name}` has no #{flag} (in `#{line}`)"
      end
    end
  end

  test "printed text loses control characters but keeps newlines and tabs" do
    out = StringIO.new
    Dobase::Command.new(config: Dobase::Config.new, out: out, json: false, user_agent: "test")
      .send(:say, "Hi \e]52;c;cHduZWQ=\a\e[2Jthere\n\ttabbed")

    assert_equal "Hi ]52;c;cHduZWQ=[2Jthere\n\ttabbed\n", out.string
  end

  test "plain text becomes escaped paragraphs" do
    html = command.send(:rich_text, "Hello <b>you</b>\nsecond line\n\nNew paragraph")

    assert_equal "<p>Hello &lt;b&gt;you&lt;/b&gt;<br>second line</p><p>New paragraph</p>", html
    assert_equal "<p>kept</p>", command.send(:rich_text, "<p>kept</p>", html: true)
  end

  test "dates accept keywords and ISO dates only" do
    assert_nil command.send(:date_param, "none")
    assert_equal Date.today.iso8601, command.send(:date_param, "today")
    assert_equal "2026-10-01", command.send(:date_param, "2026-10-01")
    assert_raises(Dobase::UsageError) { command.send(:date_param, "friday") }
  end

  test "TOOL/ID references must end in a numeric id" do
    assert_raises(Dobase::UsageError) { command.send(:tool_and_id, "104", "boards", "card") }
    assert_raises(Dobase::UsageError) { command.send(:tool_and_id, "roadmap/abc", "boards", "card") }
  end

  private

  def command
    Dobase::Command.new(config: Dobase::Config.new, out: StringIO.new, json: false, user_agent: "test")
  end

  def run_cli(*args)
    Dir.mktmpdir do |config_home|
      env = { "XDG_CONFIG_HOME" => config_home, "DOBASE_URL" => nil, "DOBASE_TOKEN" => nil }
      output, errors, status = Open3.capture3(env, RbConfig.ruby, CLI, *args)
      [ output, status, errors ]
    end
  end
end
