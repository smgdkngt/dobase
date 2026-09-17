# frozen_string_literal: true

# One way to show a byte count everywhere: "0 B", "397 B", "8.5 KB", "25 MB".
# Views use the `human_file_size` helper for blobs; records with a `file_size`
# column get `#human_file_size` from this concern. The "B" unit comes from
# config/locales/en.yml.
module HumanFileSize
  extend ActiveSupport::Concern

  def self.format(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(
      bytes.to_i, precision: 1, significant: false, strip_insignificant_zeros: true
    )
  end

  def human_file_size
    HumanFileSize.format(file_size)
  end
end
