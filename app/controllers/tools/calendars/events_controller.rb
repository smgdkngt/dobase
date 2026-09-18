# frozen_string_literal: true

module Tools
  module Calendars
    class EventsController < ApplicationController
      include ToolScoped

      # Recurrence fields besides recurrence_frequency.
      RECURRENCE_FIELDS = %w[
        recurrence_interval recurrence_days_of_week recurrence_monthly_by
        recurrence_end_type recurrence_count recurrence_until
      ].freeze

      allow_access_tokens only: %i[show create update destroy]
      before_action :set_calendar_account
      before_action :set_event, only: %i[show edit update destroy]

      def show
        respond_to do |format|
          format.html do
            render layout: false if request.headers["X-Requested-With"] == "XMLHttpRequest"
          end
          format.turbo_stream
          format.json
        end
      end

      def new
        @calendars = writable_calendars
        @calendar = default_calendar
        @event = @calendar.events.build(
          starts_at: parse_start_time(params[:starts_at]),
          ends_at: parse_end_time(params[:starts_at], params[:ends_at])
        )
        @event.load_recurrence_for_form
      end

      def create
        @calendars = writable_calendars
        @calendar = find_calendar(event_params[:calendar_id].presence || default_calendar&.id)
        @event = @calendar.events.build(event_params.except(:calendar_id))
        @event.uid = generate_uid
        @event.created_by = current_user
        @event.updated_by = current_user

        if calendar_accepts_event? && @event.save
          PushEventJob.perform_later(@event.id, :create)
          notify_event_created

          respond_to do |format|
            format.html { redirect_to tool_calendar_path(@tool), notice: "Event created successfully.", status: :see_other }
            format.json { render :show, status: :created }
          end
        else
          respond_to do |format|
            format.html { render :new, status: :unprocessable_entity }
            format.json { render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def edit
        @calendars = writable_calendars
        @event.load_recurrence_for_form
        render layout: false if turbo_frame_request?
      end

      def update
        @calendars = writable_calendars
        @event.load_recurrence_for_form if partial_recurrence_update?
        @event.assign_attributes(event_params.except(:calendar_id).merge(updated_by: current_user))
        @event.calendar = find_calendar(event_params[:calendar_id]) if event_params[:calendar_id].present?

        if calendar_accepts_event? && @event.save
          PushEventJob.perform_later(@event.id, @event.saved_change_to_calendar_id? ? :move : :update)

          respond_to do |format|
            format.html { redirect_to tool_calendar_path(@tool), notice: "Event updated successfully.", status: :see_other }
            format.json { render :show }
          end
        else
          respond_to do |format|
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity }
          end
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

        respond_to do |format|
          format.html { redirect_to tool_calendar_path(@tool), notice: "Event deleted successfully.", status: :see_other }
          format.json { head :no_content }
        end
      end

      private

      def set_calendar_account
        @calendar_account = @tool.calendar_account
        return if @calendar_account

        if request.format.json?
          render json: { error: "Calendar account not configured" }, status: :not_found
        else
          redirect_to new_tool_calendar_account_path(@tool), alert: "Please configure your calendar account first."
        end
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

      # Events can only be added to, or moved to, an enabled calendar that the
      # server accepts writes to.
      def calendar_accepts_event?
        return true unless @event.new_record? || @event.calendar_id_changed?

        if @event.calendar.read_only?
          @event.errors.add(:calendar, "is read-only")
        elsif !@event.calendar.enabled?
          @event.errors.add(:calendar, "is disabled")
        end

        @event.errors.none?
      end

      # The edit form always sends the whole recurrence. An update without a
      # recurrence_frequency that moves the start or changes part of the
      # recurrence starts from the current recurrence, so the series is rebuilt
      # around the change instead of keeping a schedule for the old start.
      def partial_recurrence_update?
        @event.is_recurring? && !event_params.key?(:recurrence_frequency) &&
          (event_params.key?(:start_time) || event_params.keys.intersect?(RECURRENCE_FIELDS))
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
        recipients = @tool.notifiable_users.where.not(id: current_user.id)
        return if recipients.none?

        CalendarEventCreatedNotifier.with(event: @event, creator: current_user, tool: @tool).deliver(recipients)
        recipients.each(&:prune_notifications!)
      end
    end
  end
end
