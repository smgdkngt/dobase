# frozen_string_literal: true

# The tool a file belongs to, by what it is attached to (Active Storage's attachment
# record). A file is shown or downloaded through a tool's address only when it lies in
# that tool (Tools::FilePreviewsController, Tools::FileDownloadsController). A kind of
# record that isn't listed here (someone's avatar, a document's pictures) is in no tool.
module FileOfATool
  def self.tool_of(record)
    case record
    when ::Files::Item then record.tool
    when ::Mails::Attachment then record.message.account.tool
    when ::Boards::Attachment then record.card.column.board.tool
    when ::Todos::Attachment then record.item.list.tool
    when ::Chats::Message then record.chat.tool
    end
  end
end
