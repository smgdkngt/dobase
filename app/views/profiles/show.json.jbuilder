json.partial! "users/user", user: @user
json.(@user, :first_name, :last_name, :timezone)
# The zone as programs know it (IANA): what the CLI's full-screen app shows times in
json.timezone_identifier ActiveSupport::TimeZone[@user.timezone.presence || "UTC"]&.tzinfo&.name

if Current.access_token
  json.access_token do
    json.(Current.access_token, :name, :permission, :agent, :created_at)
  end
end
