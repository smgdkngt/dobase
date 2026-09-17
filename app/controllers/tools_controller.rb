# frozen_string_literal: true

class ToolsController < ApplicationController
  include ToolAuthorization

  allow_access_tokens only: %i[index show create update]

  before_action :set_tool, only: [ :show, :edit, :update, :destroy ]
  before_action -> { authorize_tool_access!(@tool) }, only: [ :show, :edit ]
  before_action -> { authorize_tool_owner!(@tool) }, only: [ :update, :destroy ]

  def index
    @tools = current_user.accessible_tools.includes(:tool_type).order(updated_at: :desc)
    @owned_tool_ids = Collaborator.where(user: current_user, role: "owner").pluck(:tool_id).to_set
  end

  def show
    respond_to do |format|
      format.html { redirect_to_tool_interface }
      format.json
    end
  end

  def new
    @tool = Tool.new
    @tool_types = ToolType.enabled.order(:name)

    if params[:tool_type_id]
      @tool.tool_type = ToolType.find_by(id: params[:tool_type_id])
    end
  end

  def create
    @tool = current_user.owned_tools.build(tool_params)

    respond_to do |format|
      if @tool.save
        format.html { redirect_to @tool, notice: "#{@tool.name} created successfully." }
        format.json { render :show, status: :created }
      else
        format.html do
          @tool_types = ToolType.enabled.order(:name)
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: @tool.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    redirect_to @tool unless turbo_frame_request?
  end

  def update
    respond_to do |format|
      if @tool.update(tool_params)
        format.html { redirect_to @tool, notice: "#{@tool.name} updated successfully." }
        format.json { render :show }
      else
        format.html do
          @tool_types = ToolType.enabled.order(:name)
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { errors: @tool.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    name = @tool.name
    @tool.destroy
    redirect_to root_path, notice: "#{name} deleted successfully."
  end

  private

  def set_tool
    @tool = Tool.find(params[:id])
  end

  # API clients name the tool type by its slug ("boards", "todos", ...).
  def tool_params
    params.require(:tool).permit(:name, :tool_type_id).tap do |permitted|
      if params[:tool][:tool_type].present?
        permitted[:tool_type_id] = ToolType.enabled.find_by(slug: params[:tool][:tool_type])&.id
      end
    end
  end

  def redirect_to_tool_interface
    case @tool.tool_type.slug
    when "mail"
      redirect_to tool_mails_path(@tool)
    when "boards"
      redirect_to tool_board_path(@tool)
    when "files"
      redirect_to tool_files_path(@tool)
    when "chat"
      redirect_to tool_chat_path(@tool)
    when "docs"
      redirect_to tool_docs_path(@tool)
    when "calendar"
      redirect_to tool_calendar_path(@tool)
    when "room"
      redirect_to tool_room_path(@tool)
    when "todos"
      redirect_to tool_todo_path(@tool)
    else
      redirect_to root_path
    end
  end
end
