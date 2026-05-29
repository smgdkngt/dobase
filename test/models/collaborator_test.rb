# frozen_string_literal: true

require "test_helper"

class CollaboratorTest < ActiveSupport::TestCase
  setup do
    @collaborator = collaborators(:two_shared_board)
  end

  test "muted? returns false when muted_at is nil" do
    refute @collaborator.muted?
  end

  test "mute! sets muted_at to the current time" do
    travel_to Time.zone.local(2026, 5, 29, 9, 0) do
      @collaborator.mute!

      assert @collaborator.reload.muted?
      assert_equal Time.zone.local(2026, 5, 29, 9, 0), @collaborator.muted_at
    end
  end

  test "unmute! clears muted_at" do
    @collaborator.mute!

    @collaborator.unmute!

    assert_nil @collaborator.reload.muted_at
    refute @collaborator.muted?
  end

  test "muted scope returns only muted collaborators" do
    @collaborator.mute!

    assert_includes Collaborator.muted, @collaborator
    refute_includes Collaborator.unmuted, @collaborator
  end

  test "unmuted scope returns only collaborators without muted_at" do
    assert_includes Collaborator.unmuted, @collaborator

    @collaborator.mute!

    refute_includes Collaborator.unmuted, @collaborator
  end
end
