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

  def find_next_message(current_message, folder)
    scope = mail_folder_scope(folder)
    sent_at = current_message.sent_at

    # Next conversation (older) — the one below in the list
    scope.where.not(thread_id: current_message.thread_id)
         .where(sent_at: ...sent_at)
         .order(sent_at: :desc)
         .first ||
    # Fall back to previous conversation (newer) — the one above
    scope.where.not(thread_id: current_message.thread_id)
         .where("sent_at > ?", sent_at)
         .order(sent_at: :asc)
         .first
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
    when "sent"    then account.messages.sent
    when "starred" then account.messages.starred
    when "trash"   then account.messages.trashed
    when "archive" then account.messages.archived.not_trashed
    when "inbox"   then account.messages.inbox.not_archived
    else                account.messages.where(folder: folder).not_trashed
    end
  end
end
