class ChangeNotificationDigestDefaultToDaily < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :notification_digest, from: "off", to: "daily"
    User.where(notification_digest: "off").update_all(notification_digest: "daily")
  end
end
