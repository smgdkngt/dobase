# frozen_string_literal: true

namespace :mail do
  desc "Fetch the Content-IDs of pictures in mail saved before they were kept, so they show in its text"
  task fill_in_content_ids: :environment do
    Mails::Account.find_each { |account| FillInMailContentIdsJob.perform_later(account.id) }
  end
end
