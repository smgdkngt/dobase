# frozen_string_literal: true

module Tools
  module Calendars
    class EventsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_calendar_account
      before_action :set_event, only: %i[show edit update destroy]

      def show
        respond_to do |format|
          format.html do
            render layout: false if request.headers["X-Requested-With"] == "XMLHttpRequest"
          end
          format.turbo_stream
        end
      end

      def new
        @calendars = writable_calendars
        @calendar = default_calendar
        @event = @calendar.events.build(
          starts_at: parse_start_time(params[:starts_at]),
          ends_at: parse_end_time(params[:starts_at], params[:ends_at])
        )
      end

      def create
        @calendars = writable_calendars
        @calendar = find_calendar(event_params[:calendar_id])
        @event = @calendar.events.build(event_params.except(:calendar_id))
        @event.uid = generate_uid
        @event.created_by = current_user
        @event.updated_by = current_user

        if @event.save
          PushEventJob.perform_later(@event.id, :create)
          notify_event_created
          redirect_to tool_calendar_path(@tool), notice: "Event created successfully.", status: :see_other
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @calendars = writable_calendars
        @event.load_recurrence_for_form
        render layout: false if turbo_frame_request?
      end

      def update
        @calendars = @calendar_account.calendars.enabled.by_position
        if @event.update(event_params.merge(updated_by: current_user))
          PushEventJob.perform_later(@event.id, :update)
          redirect_to tool_calendar_path(@tool), notice: "Event updated successfully.", status: :see_other
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        # Store data needed for CalDAV delete before destroying locally
        event_data = {
          remote_href: @event.remote_href,
          etag: @event.etag,
          calendar_id: @event.calendar_id,
          uid: @event.uid
        }

        @event.destroy

        # Push delete to CalDAV server
        DeleteCalendarEventJob.perform_later(event_data)

        redirect_to tool_calendar_path(@tool), notice: "Event deleted successfully.", status: :see_other
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_calendar_account
        @calendar_account = @tool.calendar_account
        redirect_to new_tool_calendar_account_path(@tool), alert: "Please configure your calendar account first." unless @calendar_account
      end

      def set_event
        @event = @calendar_account.events.find(params[:id])
        @calendar = @event.calendar
      end

      def writable_calendars
        @calendar_account.calendars.enabled.writable.by_position
      end

      def default_calendar
        writable_calendars.find_by(is_default: true) ||
          writable_calendars.first
      end

      def find_calendar(calendar_id)
        @calendar_account.calendars.find(calendar_id)
      end

      def event_params
        params.require(:calendars_event).permit(
          :calendar_id,
          :summary,
          :description,
          :location,
          :start_time,
          :end_time,
          :all_day,
          :status,
          :recurrence_frequency,
          :recurrence_interval,
          :recurrence_monthly_by,
          :recurrence_end_type,
          :recurrence_count,
          :recurrence_until,
          recurrence_days_of_week: []
        )
      end

      def parse_start_time(starts_at_param)
        if starts_at_param.present?
          Time.zone.parse(starts_at_param)
        else
          Time.current.beginning_of_hour + 1.hour
        end
      rescue ArgumentError
        Time.current.beginning_of_hour + 1.hour
      end

      def parse_end_time(starts_at_param, ends_at_param)
        if ends_at_param.present?
          Time.zone.parse(ends_at_param)
        elsif starts_at_param.present?
          Time.zone.parse(starts_at_param) + 1.hour
        else
          Time.current.beginning_of_hour + 2.hours
        end
      rescue ArgumentError
        Time.current.beginning_of_hour + 2.hours
      end

      def generate_uid
        "#{SecureRandom.uuid}@#{Rails.application.config.x.app.name.parameterize}"
      end

      def notify_event_created
        recipients = @tool.users.where.not(id: current_user.id)
        return if recipients.none?

        CalendarEventCreatedNotifier.with(event: @event, creator: current_user, tool: @tool).deliver(recipients)
        recipients.each(&:prune_notifications!)
      end
    end
  end
end
