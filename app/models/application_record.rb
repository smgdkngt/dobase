# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  include Translation::Methods

  primary_abstract_class
end
