# frozen_string_literal: true

one_other = ->(n) { n.abs == 1 && n.is_a?(Integer) ? :one : :other }
zero_one_other = ->(n) { n.abs <= 1 ? :one : :other }
other = ->(_n) { :other }
few = ->(n) { (2..4).cover?(n % 10) && !(12..14).cover?(n % 100) }

one_many_other = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :other
  elsif n == 1
    :one
  elsif !n.zero? && (n % 1_000_000).zero?
    :many
  else
    :other
  end
end

zero_one_many_other = ->(n) do
  n = n.abs
  if n < 2
    :one
  elsif n.is_a?(Integer) && (n % 1_000_000).zero?
    :many
  else
    :other
  end
end

ar = ->(n) do
  n = n.abs
  if n.zero?
    :zero
  elsif n == 1
    :one
  elsif n == 2
    :two
  elsif !n.is_a?(Integer)
    :other
  elsif (3..10).cover?(n % 100)
    :few
  elsif (11..99).cover?(n % 100)
    :many
  else
    :other
  end
end

he = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :other
  elsif n == 1
    :one
  elsif n == 2
    :two
  else
    :other
  end
end

pl = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :other
  elsif n == 1
    :one
  elsif few.call(n)
    :few
  else
    :many
  end
end

uk = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :other
  elsif n % 10 == 1 && n % 100 != 11
    :one
  elsif few.call(n)
    :few
  else
    :many
  end
end

cs = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :many
  elsif n == 1
    :one
  elsif (2..4).cover?(n)
    :few
  else
    :other
  end
end

ro = ->(n) do
  n = n.abs
  if !n.is_a?(Integer)
    :few
  elsif n == 1
    :one
  elsif n.zero? || (2..19).cover?(n % 100)
    :few
  else
    :other
  end
end

rules = {
  en: one_other, nl: one_other, de: one_other, tr: one_other, sv: one_other, da: one_other, nb: one_other, fi: one_other,
  fa: zero_one_other, hi: zero_one_other,
  es: one_many_other, it: one_many_other,
  fr: zero_one_many_other, pt: zero_one_many_other,
  ja: other, ko: other, zh: other, id: other,
  ar: ar, he: he, pl: pl, uk: uk, cs: cs, ro: ro
}

rules.transform_values { |rule| { i18n: { plural: { rule: rule } } } }
