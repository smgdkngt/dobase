# frozen_string_literal: true

# A new order for a column or list when only some of its entries were shown
# (a filter was on): the requested ids in their new order, with every entry
# that wasn't shown put back right after the entry it followed before.
module KeepHiddenInPlace
  def self.call(current, requested)
    order = requested.dup
    (current - requested).each do |hidden|
      before = current.take(current.index(hidden)).reverse.find { |id| order.include?(id) }
      order.insert(before ? order.index(before) + 1 : 0, hidden)
    end
    order
  end
end
