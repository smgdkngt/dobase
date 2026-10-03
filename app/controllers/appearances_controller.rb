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

  # Changes what the request names: the theme, the typeface, whether there is a theme
  # for light and one for dark, or several of those. A theme with a scheme ("light"
  # or "dark") is the one for that; without, it is the one theme for both.
  def update
    name = params[:theme].to_s.strip

    if name.present? && Theme.find(name).nil? && Theme.clean_palette(colors).nil?
      return respond_to do |format|
        format.html { redirect_to edit_profile_path(tab: "appearance"), alert: "That theme doesn't exist.", status: :see_other }
        format.json { render json: { error: "Unknown theme. Pick one of the built-in themes, or send its colors." }, status: :unprocessable_entity }
      end
    end

    if params.key?(:follow_system)
      current_user.follow_system(ActiveModel::Type::Boolean.new.cast(params[:follow_system]) || false, seen_in: scheme)
    end
    current_user.choose_theme(name, colors, scheme: params[:scheme].to_s.presence_in(%w[light dark])) if params.key?(:theme)
    current_user.choose_typeface(params[:typeface]) if params.key?(:typeface)

    respond_to do |format|
      format.html { redirect_to edit_profile_path(tab: "appearance"), status: :see_other }
      format.json { render :show }
    end
  end

  private

  # Light or dark: what the request says, or what this browser said it is. It picks
  # between someone's two themes; a client that says neither gets the light one.
  def scheme
    params[:scheme].to_s.presence_in(%w[light dark]) || browser_scheme
  end
  helper_method :scheme

  def colors
    params[:colors].permit(:mode, *Theme::COLORS).to_h if params[:colors].respond_to?(:permit)
  end
end
