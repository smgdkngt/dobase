module DemoTestHelper
  # Runs the block as a demo instance (DEMO_MODE=true) would
  def in_demo_mode
    previous = ENV["DEMO_MODE"]
    ENV["DEMO_MODE"] = "true"
    yield
  ensure
    ENV["DEMO_MODE"] = previous
  end

  # The tool types the demo workspace uses; the fixtures leave out chat
  def create_demo_tool_types
    ToolType.find_or_create_by!(slug: "chat") { |type| type.assign_attributes(name: "Chat", icon: "messages-square", enabled: true) }
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include DemoTestHelper
end
