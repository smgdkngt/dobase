# frozen_string_literal: true

# The colours and the typeface someone sees the app in: a built-in theme, a palette of
# their own, or the app's own look. It is cosmetic, so a token may set it, which is how
# `dobase theme sync` keeps the app on the theme of an Omarchy desktop.
class AppearancesController < ApplicationController
  allow_access_tokens

  def show
    respond_to do |format|
      format.html { redirect_to edit_profile_path(tab: "appearance") }
      format.json
    end
  end

  # Changes what the request names: the theme, the typeface, or both
  def update
    name = params[:theme].to_s.strip

    if name.present? && Theme.find(name).nil? && Theme.clean_palette(colors).nil?
      return respond_to do |format|
        format.html { redirect_to edit_profile_path(tab: "appearance"), alert: "That theme doesn't exist.", status: :see_other }
        format.json { render json: { error: "Unknown theme. Pick one of the built-in themes, or send its colors." }, status: :unprocessable_entity }
      end
    end

    current_user.choose_theme(name, colors) if params.key?(:theme)
    current_user.choose_typeface(params[:typeface]) if params.key?(:typeface)

    respond_to do |format|
      format.html { redirect_to edit_profile_path(tab: "appearance"), status: :see_other }
      format.json { render :show }
    end
  end

  private

  def colors
    params[:colors].permit(:mode, *Theme::COLORS).to_h if params[:colors].respond_to?(:permit)
  end
end
