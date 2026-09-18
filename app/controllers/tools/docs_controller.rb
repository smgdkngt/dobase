# frozen_string_literal: true

module Tools
  class DocsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      @documents = @tool.documents.with_rich_text_content.includes(:updated_by, :locked_by).ordered

      respond_to do |format|
        format.html do
          @view_mode = params[:view].presence_in(%w[grid list]) || cookies[:docs_view] || "grid"

          if params[:view].present? && params[:view] != cookies[:docs_view]
            cookies[:docs_view] = { value: params[:view], expires: 1.year.from_now }
          end
        end
        format.json
      end
    end
  end
end
