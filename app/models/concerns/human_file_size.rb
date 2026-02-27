# frozen_string_literal: true

module HumanFileSize
  extend ActiveSupport::Concern

  def human_file_size
    return "0 B" if file_size.blank? || file_size.zero?

    units = %w[B KB MB GB TB]
    size = file_size.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    format("%.1f %s", size, units[unit_index])
  end
end
