# frozen_string_literal: true

# A new folder gets a plain name. (Mail moves to any folder the server has:
# Mails::Account#folder_to_move_to.)
module FolderValidation
  extend ActiveSupport::Concern

  VALID_FOLDER_NAME = /\A[a-zA-Z0-9 _.\-\/]+\z/
  MAX_FOLDER_NAME_LENGTH = 100

  private

  def valid_folder_name?(name)
    name.present? && name.length <= MAX_FOLDER_NAME_LENGTH && name.match?(VALID_FOLDER_NAME)
  end
end
