# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def card_assigned
    @notification = params[:notification]
    @card = params[:card]
    @assigner = params[:assigner]
    @tool = params[:tool]
    @recipient = params[:recipient]

    mail(
      to: @recipient.email_address,
      subject: "#{@assigner.name} assigned you to #{@card.title}"
    )
  end

  def todo_assigned
    @notification = params[:notification]
    @item = params[:item]
    @assigner = params[:assigner]
    @tool = params[:tool]
    @recipient = params[:recipient]

    mail(
      to: @recipient.email_address,
      subject: "#{@assigner.name} assigned you to #{@item.title}"
    )
  end
end
