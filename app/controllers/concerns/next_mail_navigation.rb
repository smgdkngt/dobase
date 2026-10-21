# frozen_string_literal: true

module NextMailNavigation
  private

  def redirect_to_next_mail_or_fallback(next_msg, folder:, notice:)
    if next_msg
      redirect_to tool_mail_path(@tool, next_msg, folder: folder), notice: notice
    else
      redirect_to tool_mails_path(@tool, folder: folder), notice: notice
    end
  end

  # The conversation that takes the place of this one in the folder's list once it has
  # gone from there: the one below it, or at the bottom of the list the one above. The
  # list has conversations by their newest message, and opens one on that message.
  def find_next_message(current_message, folder)
    scope = mail_folder_scope(folder)
    latest = scope.where(thread_id: current_message.thread_id).maximum(:sent_at) || current_message.sent_at
    others = scope.where.not(thread_id: current_message.thread_id).group(:thread_id)

    thread_id = others.having("MAX(mail_messages.sent_at) < ?", latest).order(Arel.sql("MAX(mail_messages.sent_at) DESC")).pick(:thread_id) ||
                others.having("MAX(mail_messages.sent_at) > ?", latest).order(Arel.sql("MAX(mail_messages.sent_at) ASC")).pick(:thread_id)
    scope.where(thread_id: thread_id).order(sent_at: :desc).first if thread_id
  end

  # Archiving and trashing act on conversations, the way the folder's list shows them:
  # the messages, and the other messages of their conversations in that folder
  def with_their_conversations(messages, folder:)
    thread_ids = messages.filter_map(&:thread_id)
    (messages.to_a + mail_folder_scope(folder).where(thread_id: thread_ids).to_a).uniq
  end

  def mail_folder_scope(folder)
    account = @tool.mail_account
    case folder
    when "sent"    then account.messages.sent.not_archived
    when "starred" then account.messages.starred
    when "trash"   then account.messages.trashed
    when "junk"    then account.messages.junk
    when "archive" then account.archived_messages
    when "inbox"   then account.messages.inbox.not_archived
    else                account.messages.where(folder: folder).not_archived.not_trashed
    end
  end
end
