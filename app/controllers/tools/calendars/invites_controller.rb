# frozen_string_literal: true

module Tools
  module Calendars
    class InvitesController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_calendar_account
      before_action :set_invite, only: :destroy

      # POST /tools/:tool_id/calendar/invites
      # Accept an invite and create event
      def create
        @invite = accessible_invites.find(params[:invite_id] || params[:id])
        @calendar = find_target_calendar

        # Create event from invite
        @event = @calendar.events.build(
          uid: @invite.uid,
          summary: @invite.summary.presence || ::Calendars::Event::UNTITLED,
          description: @invite.description,
          location: @invite.location,
          starts_at: @invite.starts_at,
          ends_at: @invite.ends_at,
          all_day: @invite.all_day,
          organizer_email: @invite.organizer_email,
          organizer_name: @invite.organizer_name,
          attendees: @invite.attendees,
          raw_icalendar: @invite.raw_icalendar
        )

        if @event.save
          @invite.update!(
            status: "accepted",
            added_to_calendar: @calendar,
            created_event: @event
          )

          PushEventJob.perform_later(@event.id, :create)
          # Back to the email, like declining. The calendar answers Turbo form redirects with a refresh stream,
          # which would refresh the mail page anyway instead of navigating to the calendar.
          redirect_back fallback_location: tool_calendar_path(@tool, week_start: @event.starts_at.to_date), notice: "Invite accepted and added to calendar."
        else
          redirect_back fallback_location: tool_calendar_path(@tool), alert: "Failed to create event: #{@event.errors.full_messages.join(', ')}"
        end
      end

      # DELETE /tools/:tool_id/calendar/invites/:id
      # Decline an invite
      def destroy
        @invite.update!(status: "declined")
        redirect_back fallback_location: tool_calendar_path(@tool), notice: "Invite declined."
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_calendar_account
        @calendar_account = @tool.calendar_account
        redirect_to new_tool_calendar_account_path(@tool), alert: "Please configure your calendar account first." unless @calendar_account
      end

      def set_invite
        @invite = accessible_invites.find(params[:id])
      end

      # Invites arrive by mail, so they belong to whoever can open the mail tool
      # that received them. The calendar tool in the URL says nothing about that.
      def accessible_invites
        ::Calendars::Invite.joins(mail_message: :account)
          .where(mail_accounts: { tool_id: current_user.accessible_tools.select(:id) })
      end

      def find_target_calendar
        if params[:calendar_id].present?
          @calendar_account.calendars.find(params[:calendar_id])
        else
          @calendar_account.calendars.find_by(is_default: true) ||
            @calendar_account.calendars.enabled.first
        end
      end
    end
  end
end
