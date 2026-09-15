# Renders `user` under `key`, or null when there is none (unassigned, deleted...).
if user
  json.set! key do
    json.partial! "users/user", user: user
  end
else
  json.set! key, nil
end
