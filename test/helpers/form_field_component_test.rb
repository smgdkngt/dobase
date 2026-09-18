# frozen_string_literal: true

require "test_helper"

# The form_field component is where a field's label, help text and error
# message get tied together, so assert that wiring once, here.
class FormFieldComponentTest < ActionView::TestCase
  test "the label points at the input" do
    render partial: "components/form_field", locals: { label: "Email", name: "email_address" }

    assert_select "label[for=?]", "email_address", text: /Email/
    assert_select "input#email_address"
  end

  test "help text is tied to the input with aria-describedby" do
    render partial: "components/form_field",
      locals: { label: "Name", name: "name", help: "Give your tool a name" }

    assert_select "input[aria-describedby=?]", "name-help"
    assert_select "p#name-help", text: "Give your tool a name"
    assert_select "input[aria-invalid]", count: 0
  end

  test "an error marks the input invalid and is tied to it" do
    render partial: "components/form_field",
      locals: { label: "Name", name: "name", error: "can't be blank" }

    assert_select "input[aria-invalid=?][aria-describedby=?]", "true", "name-error"
    assert_select "p#name-error.error-text", text: "can't be blank"
  end

  test "a required field says so for a screen reader as well as visually" do
    render partial: "components/form_field",
      locals: { label: "Name", name: "name", required: true }

    assert_select "input[required]"
    assert_select "label[for=?] .sr-only", "name", text: "(required)"
  end
end
