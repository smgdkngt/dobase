require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "deleting an account leaves a tool that another owner still owns" do
    tool = tools(:shared_board)
    tool.collaborators.find_by(user: users(:two)).update!(role: "owner")

    users(:one).destroy!

    assert Tool.exists?(tool.id), "co-owned tool was destroyed with its creator"
    assert_equal users(:two), tool.reload.owner
  end

  test "deleting an account destroys a tool nobody else owns" do
    tool = tools(:shared_board)

    users(:one).destroy!

    assert_not Tool.exists?(tool.id)
  end

  test "deleting an account keeps what they wrote in a tool that lives on, without them" do
    author, co_owner = users(:one), users(:two)
    board_tool = tools(:shared_board)
    board_tool.collaborators.find_by(user: co_owner).update!(role: "owner")
    column = board_tool.board.columns.create!(name: "Doing", position: 0)
    card = column.cards.create!(title: "Plan", created_by: author, updated_by: author, assigned_user: author)
    comment = Boards::Comment.create!(card: card, user: author, body: "On it")
    Boards::ColumnCollapse.create!(column: column, user: author)
    invitation = board_tool.invitations.create!(email: "new@example.com", invited_by: author)

    chat_tool = Tool.create!(name: "Talk", owner: author, tool_type: ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle"))
    chat_tool.collaborators.create!(user: co_owner, role: "owner")
    message = chat_tool.chat.messages.create!(user: author, body: "Hello")
    message.reactions.create!(user: author, emoji: "👍")

    author.destroy!

    assert_nil card.reload.created_by
    assert_nil card.assigned_user
    assert_nil comment.reload.user
    assert_nil message.reload.user
    assert_empty message.reactions
    assert_not Boards::ColumnCollapse.exists?(user_id: author.id)
    assert_not Invitation.exists?(invitation.id)
    assert_equal "On it", comment.body.to_plain_text
  end

  test "a new comment still needs its author" do
    comment = Boards::Comment.new(card: cards(:first_task), body: "Hi")

    assert_not comment.valid?
    assert_includes comment.errors[:user], "can't be blank"
  end

  test "a default avatar looks the same for the same person, in two different label colours" do
    look = users(:one).avatar_look

    assert_equal look, User.find(users(:one).id).avatar_look
    assert_includes User::AVATAR_HUES, look[:hue]
    assert_includes User::AVATAR_HUES, look[:second]
    assert_not_equal look[:hue], look[:second]
    assert_includes 1..User::AVATAR_PATTERNS, look[:pattern]
  end

  test "people get different default avatars" do
    looks = (1..40).map { |id| User.new(id: id).avatar_look }

    assert_operator looks.uniq.size, :>, 30
    assert_equal User::AVATAR_HUES.sort, looks.map { |look| look[:hue] }.uniq.sort
    looks.each { |look| assert_not_equal look[:hue], look[:second] }
  end

  test "one theme whatever the system says, until there is one for light and one for dark" do
    user = users(:one)
    user.choose_theme("nord")

    assert_equal "nord", user.theme("light").name
    assert_equal "nord", user.theme("dark").name

    user.choose_theme("catppuccin-latte", scheme: "light")
    user.choose_theme("tokyo-night", scheme: "dark")

    assert user.theme_follows_system?
    assert_equal "catppuccin-latte", user.theme("light").name
    assert_equal "tokyo-night", user.theme("dark").name
    # A client that doesn't say which gets the light one
    assert_equal "catppuccin-latte", user.theme.name

    # A theme without a scheme is the one theme again
    user.choose_theme("gruvbox")
    assert_not user.theme_follows_system?
    assert_nil user.dark_theme_name
    assert_equal "gruvbox", user.theme("dark").name
  end

  test "going to two themes and back keeps what is on in the browser that asked" do
    user = users(:one)
    user.choose_theme("tokyo-night")

    # A dark theme becomes the one for dark; light gets the app's own look
    user.follow_system(true, seen_in: "dark")
    assert_equal "tokyo-night", user.theme("dark").name
    assert_nil user.theme("light")

    user.choose_theme("catppuccin-latte", scheme: "light")
    user.follow_system(false, seen_in: "dark")
    assert_not user.theme_follows_system?
    assert_equal "tokyo-night", user.theme.name

    user.choose_theme("catppuccin-latte")
    user.follow_system(true, seen_in: "light")
    assert_equal "catppuccin-latte", user.theme("light").name
    assert_nil user.theme("dark")
    user.follow_system(false, seen_in: "light")
    assert_equal "catppuccin-latte", user.theme("dark").name
  end
end
