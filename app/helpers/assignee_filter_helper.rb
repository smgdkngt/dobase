# frozen_string_literal: true

module AssigneeFilterHelper
  include Translation::Methods

  # Filters an in-memory collection of records by their assigned_user_id.
  # Supports symbolic values "me" and "unassigned", or a user id.
  # Returns the original collection when the filter is blank.
  def filter_by_assignee(records, filter)
    case filter
    when "me"         then records.select { |r| r.assigned_user_id == current_user.id }
    when "unassigned" then records.select { |r| r.assigned_user_id.nil? }
    when /\A\d+\z/    then records.select { |r| r.assigned_user_id == filter.to_i }
    else                   records
    end
  end

  # Label shown in the active filter chip / heading.
  def assignee_filter_label(filter, collaborators)
    case filter
    when "me"         then _("Assigned to me")
    when "unassigned" then _("Unassigned")
    when /\A\d+\z/
      user = collaborators.find { |u| u.id == filter.to_i }
      user ? _("Assigned to %{name}", name: user.name) : nil
    end
  end
end
