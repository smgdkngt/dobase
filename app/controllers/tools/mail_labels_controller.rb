# frozen_string_literal: true

module Tools
  class MailLabelsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :set_mail_account
    before_action :set_label, only: [ :update, :destroy ]

    def index
      labels = @mail_account.labels.order(:name)
      render json: labels.map { |label| label_json(label) }
    end

    def create
      label = @mail_account.labels.build(label_params)

      if label.save
        render json: label_json(label), status: :created
      else
        render json: { errors: label.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @label.update(label_params)
        render json: label_json(@label)
      else
        render json: { errors: @label.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @label.destroy
      head :no_content
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    def set_mail_account
      @mail_account = @tool.mail_account
      unless @mail_account
        render json: { error: "Mail account not configured" }, status: :not_found
      end
    end

    def set_label
      @label = @mail_account.labels.find(params[:id])
    end

    def label_params
      params.require(:label).permit(:name, :color)
    end

    def label_json(label)
      {
        id: label.id,
        name: label.name,
        color: label.color,
        created_at: label.created_at,
        updated_at: label.updated_at
      }
    end
  end
end
