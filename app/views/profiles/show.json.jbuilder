json.partial! "users/user", user: @user
json.(@user, :first_name, :last_name, :timezone)

if Current.access_token
  json.access_token do
    json.(Current.access_token, :name, :permission, :created_at)
  end
end
