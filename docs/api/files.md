# Files

## List a folder

`GET /tools/:tool_id/files` lists the folders and files at the top level. Add
`?folder_id=5` to list that folder instead. `folder` is `null` at the top
level, and `breadcrumbs` are the folders above it, from the top down. `shared`
is true when a folder or file has a [share link](#share-links).

```json
{
  "tool": { "id": 5, "name": "Team Files", "type": "files", "url": "...", "created_at": "...", "updated_at": "..." },
  "url": "https://dobase.example.com/tools/5/files?folder_id=5",
  "folder": { "id": 5, "name": "Photos", "parent_id": 1 },
  "breadcrumbs": [
    { "id": 1, "name": "Brand Assets", "parent_id": null }
  ],
  "folders": [
    {
      "id": 6,
      "name": "Launch Event",
      "parent_id": 5,
      "shared": false,
      "url": "https://dobase.example.com/tools/5/files?folder_id=6",
      "created_at": "2026-09-14T15:52:04.113Z",
      "updated_at": "2026-09-14T15:52:04.113Z"
    }
  ],
  "files": [
    {
      "id": 16,
      "name": "budget.csv",
      "content_type": "text/csv",
      "file_size": 34,
      "folder_id": 5,
      "creator": { "id": 1, "name": "Sophie Chen", "email_address": "sophie@moonshot-snacks.com" },
      "shared": false,
      "url": "https://dobase.example.com/tools/5/files/items/16",
      "download_url": "https://dobase.example.com/tools/5/files/items/16/download",
      "created_at": "2026-09-14T15:52:04.323Z",
      "updated_at": "2026-09-14T15:52:04.336Z"
    }
  ]
}
```

`file_size` is in bytes.

## Files

### Show

`GET /tools/:tool_id/files/items/:id` returns the file fields above plus
`share`, its public link or `null`:

```json
{
  "id": 12,
  "name": "team-contacts.txt",
  "shared": true,
  "share": {
    "url": "https://dobase.example.com/s/Qm9vbXNoYXJlLWxpbmstZXhhbXBsZS10b2tlbg",
    "expires_at": "2026-10-01T00:00:00.000Z",
    "password_protected": true,
    "download_count": 0,
    "created_at": "2026-09-14T15:52:05.235Z"
  }
}
```

### Upload

`POST /tools/:tool_id/files/uploads` as `multipart/form-data` with one or more
`files[]` fields (or a single `file`) and an optional `folder_id`. Each file can
be up to 200 MB. Returns `201` and an array with the new files, and lets the
tool's collaborators know.

```bash
curl -H "Authorization: Bearer $DOBASE_TOKEN" -H "Accept: application/json" \
  -F "files[]=@budget.csv" -F "files[]=@launch-notes.md" -F folder_id=5 \
  https://dobase.example.com/tools/5/files/uploads
```

When a file is refused, because it is too large or a blocked type such as
`.exe` or `.sh`, none of the files are saved and you get `422`:

```json
{ "errors": ["deploy.sh: File type .sh is not allowed for security reasons"] }
```

### Download

`GET /tools/:tool_id/files/items/:item_id/download` sends the file itself, as
an attachment with its name. This is the `download_url` of a file.

### Rename and move

`PATCH /tools/:tool_id/files/items/:id` with `{"name": "contacts.txt"}` renames
the file, and `{"folder_id": 3}` moves it into folder 3. Use `null` to move it
to the top level. A folder of another tool is `404`. Returns the file.

### Delete

`DELETE /tools/:tool_id/files/items/:id` returns `204`.

## Folders

- `POST /tools/:tool_id/files/folders` with `{"name": "Launch Event", "parent_id": 5}`
  creates a folder, at the top level without `parent_id`, and returns `201` and
  the folder as it appears in the list above.
- `PATCH /tools/:tool_id/files/folders/:id` with `{"name": "Product Photos"}`
  renames it, and `{"parent_id": 1}` moves it into folder 1 (`null` for the top
  level). Returns the folder. Moving a folder into itself or one of its
  subfolders is `422`. Folders nest at most 10 levels deep.
- `DELETE /tools/:tool_id/files/folders/:id` deletes the folder with everything
  in it, and returns `204`.
- `GET /tools/:tool_id/files/folders/:folder_id/download` sends a zip of the
  folder, subfolders included.

## Share links

A share link is a public URL. Anyone who has it can download the file, or
browse and download the folder, without signing in.

`GET /tools/:tool_id/files/items/:item_id/share` for a file, or
`GET /tools/:tool_id/files/folders/:folder_id/share` for a folder, returns the
link, or `404` when there is none.

Links are created and removed in the browser only. Tokens get `403`, because a
public link made with a leaked token would keep working after the token is revoked.

```json
{
  "url": "https://dobase.example.com/s/Qm9vbXNoYXJlLWxpbmstZXhhbXBsZS10b2tlbg",
  "expires_at": "2026-10-01T00:00:00.000Z",
  "password_protected": true,
  "download_count": 0,
  "created_at": "2026-09-14T15:52:05.235Z"
}
```

The password is never returned, only whether there is one.
