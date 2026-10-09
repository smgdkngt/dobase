# frozen_string_literal: true

# What happened in someone's tools, by number: "everything after N". This is what
# a listener outside the browser reads (`dobase events`), each time EventsChannel
# says there is something and every few minutes besides.
#
# The answer ends with a `cursor`: the number to ask after next time. It moves on
# past events that are someone else's or were filtered away, so a listener with
# little to hear doesn't fall a week behind and into a gap. Asked without `after`
# or `since`, it only says where the stream is now.
class EventsController < ApplicationController
  PAGE = 200

  allow_access_tokens

  def index
    # Read first: what is written while this request runs is the next one's
    newest = Event.maximum(:id).to_i
    after = Integer(params[:after], exception: false) if params[:after].present?
    since = time_of(params[:since]) if params[:since].present?
    return render_error("since isn't a time") if params[:since].present? && since.nil?
    return render_error("after isn't a number") if params[:after].present? && (after.nil? || after.negative?)

    kinds = Array(params[:kind]).compact_blank
    unknown = kinds.reject { |kind| Event.kind?(kind) }
    return render_error("Unknown kind: #{unknown.join(", ")}. Kinds are #{Event::KINDS.join(", ")}, or a family like mail.") if unknown.any?

    @gap = after.present? && Event.gap_after?(after)
    events = after.nil? && since.nil? || after.to_i > newest ? Event.none : listed(newest, after, since, kinds)
    @events = events.first(PAGE)
    @more = events.size > PAGE
    @cursor = @more ? @events.last.id : newest
    @tools = Tool.where(id: @events.map(&:tool_id).uniq).includes(:tool_type).index_by(&:id)

    respond_to { |format| format.json }
  end

  private
    def listed(newest, after, since, kinds)
      events = Event.visible_to(Current.user).where(id: ..newest).includes(:user)
      events = events.where(id: (after + 1)..) if after
      events = events.where(created_at: since..) if since
      events = events.where(tool_id: Array.wrap(params[:tool]).grep(String).map(&:to_i)) if params[:tool].present?
      events = events.of_kinds(kinds) if kinds.any?
      events = events.not_made_with(Current.access_token) if skip_own?
      events.order(:id).limit(PAGE + 1).to_a
    end

    def time_of(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def skip_own?
      Current.access_token && ActiveModel::Type::Boolean.new.cast(params[:skip_own])
    end

    def render_error(message)
      render json: { error: message }, status: :unprocessable_entity
    end
end
