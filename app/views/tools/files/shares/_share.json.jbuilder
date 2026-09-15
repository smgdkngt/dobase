# The public link. The password and its digest never leave the server.
json.url share_url(share.token)
json.expires_at share.expires_at
json.password_protected share.password_protected?
json.(share, :download_count, :created_at)
