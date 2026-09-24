use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use crate::command::{Args, Ctx, Definition, Flag, Result, bytes, command, count, day, fail, flag, moment, quoted, switch, usage};
use crate::value::{Json, compact, is_digits, join};

fn download_flags() -> Vec<Flag> {
    vec![flag("output", "PATH", "Save to PATH, or into PATH when it is a directory"), switch("force", "Overwrite an existing file")]
}

pub fn definitions() -> Vec<Definition> {
    vec![
        command(
            "file list",
            "List the folders and files at the top level, or in FOLDER (a folder id)",
            &["TOOL", "[FOLDER]"],
            vec![],
            list,
        ),
        command("file show", "Show a file's details and its public link, if it has one", &["TOOL/FILE"], vec![], show),
        command(
            "file upload",
            "Upload files (200 MB max each), to the top level unless --folder",
            &["TOOL", "PATH..."],
            vec![flag("folder", "FOLDER", "Folder id to upload into")],
            upload,
        ),
        command(
            "file download",
            "Download a file, to its own name in the current directory unless --output",
            &["TOOL/FILE"],
            download_flags(),
            download_file,
        ),
        command("file rename", "Rename a file", &["TOOL/FILE", "NAME"], vec![], rename),
        command(
            "file move",
            "Move a file into FOLDER (a folder id), or to the top level with root",
            &["TOOL/FILE", "FOLDER"],
            vec![],
            move_file,
        ),
        command("file delete", "Delete a file permanently", &["TOOL/FILE"], vec![], delete),
        command(
            "folder create",
            "Create a folder, at the top level unless --parent",
            &["TOOL", "NAME"],
            vec![flag("parent", "FOLDER", "Folder id to create it in")],
            folder_create,
        ),
        command("folder rename", "Rename a folder", &["TOOL/FOLDER", "NAME"], vec![], folder_rename),
        command(
            "folder move",
            "Move a folder into PARENT (a folder id), or to the top level with root",
            &["TOOL/FOLDER", "PARENT"],
            vec![],
            folder_move,
        ),
        command("folder delete", "Delete a folder and everything in it, permanently", &["TOOL/FOLDER"], vec![], folder_delete),
        command(
            "folder download",
            "Download a folder and everything in it as a zip, to FOLDER-NAME.zip unless --output",
            &["TOOL/FOLDER"],
            download_flags(),
            folder_download,
        ),
    ]
}

fn list(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("files"))?;
    let folder = args.get(1).map(folder_id).transpose()?.flatten();
    let listing = ctx.get(&format!("/tools/{}/files", tool["id"].s()), &[("folder_id", folder.map(|id| id.to_string()))])?;

    ctx.output(&listing, |ctx| {
        let mut trail = vec![tool["name"].s()];
        trail.extend(listing["breadcrumbs"].items().iter().map(|crumb| crumb["name"].s()));
        trail.extend(listing["folder"]["name"].opt());
        let location = if listing["folder"].truthy() {
            format!("folder {}/{}", tool["id"].s(), listing["folder"]["id"].s())
        } else {
            format!("files {}", tool["id"].s())
        };
        ctx.say(format!("{} ({location}) {}", trail.join(" / "), listing["url"].s()));
        ctx.blank();

        let shared = |entry: &Value| if entry["shared"].truthy() { "shared".to_string() } else { String::new() };
        let mut rows: Vec<Vec<String>> = listing["folders"]
            .items()
            .iter()
            .map(|entry| {
                vec![
                    format!("folder {}/{}", tool["id"].s(), entry["id"].s()),
                    entry["name"].s(),
                    String::new(),
                    String::new(),
                    shared(entry),
                ]
            })
            .collect();
        rows.extend(listing["files"].items().iter().map(|entry| {
            vec![
                format!("{}/{}", tool["id"].s(), entry["id"].s()),
                entry["name"].s(),
                bytes(&entry["file_size"]),
                day(&entry["created_at"]).unwrap_or_default(),
                shared(entry),
            ]
        }));
        if rows.is_empty() {
            ctx.say("  (empty)");
        } else {
            ctx.table(rows, 2);
        }
        Ok(())
    })
}

fn show(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "file")?;
    let file = ctx.get(&format!("/tools/{}/files/items/{id}", tool["id"].s()), &[])?;

    ctx.output(&file, |ctx| {
        ctx.say(format!("{} (file {}/{})", file["name"].s(), tool["id"].s(), file["id"].s()));
        let folder = match file["folder_id"].opt() {
            Some(folder) => format!("folder {}/{folder}", tool["id"].s()),
            None => "top level".to_string(),
        };
        ctx.field("Folder", folder);
        ctx.field("Type", file["content_type"].s());
        ctx.field("Size", bytes(&file["file_size"]));
        ctx.field("Created", join([moment(&file["created_at"]), file["creator"]["name"].opt()], " by "));
        ctx.field("URL", file["url"].s());
        ctx.field("Download", file["download_url"].s());
        if file["share"].truthy() {
            ctx.field("Shared", share_summary(&file["share"]));
        }
        Ok(())
    })
}

fn upload(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("files"))?;
    let paths = args.rest(1);
    if let Some(path) = paths.iter().find(|path| !Path::new(path).is_file()) {
        fail!("{path} is not a file.");
    }
    let folder = args.flag("folder").map(folder_id).transpose()?.flatten();

    let files: Vec<(&str, &str)> = paths.iter().map(|path| ("files[]", path.as_str())).collect();
    let fields: Vec<(&str, String)> = folder.map(|id| ("folder_id", id.to_string())).into_iter().collect();
    let uploaded = ctx.api()?.upload(&format!("/tools/{}/files/uploads", tool["id"].s()), &files, &fields)?;
    ctx.output(&uploaded, |ctx| {
        for file in uploaded.items() {
            ctx.say(format!(
                "Uploaded {} ({}) to {} as {}/{}.",
                file["name"].s(),
                bytes(&file["file_size"]),
                place(&tool, &file["folder_id"]),
                tool["id"].s(),
                file["id"].s()
            ));
        }
        Ok(())
    })
}

fn download_file(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "file")?;
    let mut file = ctx.get(&format!("/tools/{}/files/items/{id}", tool["id"].s()), &[])?;

    let path = download(ctx, &format!("/tools/{}/files/items/{id}/download", tool["id"].s()), &file["name"].s(), args)?;
    file["path"] = json!(path);
    ctx.output(&file, |ctx| {
        ctx.say(format!("Downloaded {} ({}) to {path}.", file["name"].s(), bytes(&file["file_size"])));
        Ok(())
    })
}

fn rename(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "file")?;
    let file = ctx.patch(&format!("/tools/{}/files/items/{id}", tool["id"].s()), json!({ "name": args.at(1) }))?;
    ctx.output(&file, |ctx| {
        ctx.say(format!("Renamed file {}/{} to {}.", tool["id"].s(), file["id"].s(), quoted(&file["name"].s())));
        Ok(())
    })
}

fn move_file(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "file")?;
    let folder = folder_id(args.at(1))?;
    let file = ctx.patch(&format!("/tools/{}/files/items/{id}", tool["id"].s()), json!({ "folder_id": folder }))?;
    ctx.output(&file, |ctx| {
        ctx.say(format!(
            "Moved file {}/{} {} to {}.",
            tool["id"].s(),
            file["id"].s(),
            quoted(&file["name"].s()),
            place(&tool, &file["folder_id"])
        ));
        Ok(())
    })
}

fn delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "file")?;
    ctx.delete(&format!("/tools/{}/files/items/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted file {}/{id}.", tool["id"].s()));
        Ok(())
    })
}

fn folder_create(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let tool = ctx.tool(args.at(0), Some("files"))?;
    let parent = args.flag("parent").map(folder_id).transpose()?.flatten();
    let folder =
        ctx.post(&format!("/tools/{}/files/folders", tool["id"].s()), compact(json!({ "name": args.at(1), "parent_id": parent })))?;

    let location =
        if folder["parent_id"].truthy() { format!("in {}", place(&tool, &folder["parent_id"])) } else { "at the top level".to_string() };
    ctx.output(&folder, |ctx| {
        ctx.say(format!(
            "Created folder {}/{} {} {location}: {}",
            tool["id"].s(),
            folder["id"].s(),
            quoted(&folder["name"].s()),
            folder["url"].s()
        ));
        Ok(())
    })
}

fn folder_rename(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "folder")?;
    let folder = ctx.patch(&format!("/tools/{}/files/folders/{id}", tool["id"].s()), json!({ "name": args.at(1) }))?;
    ctx.output(&folder, |ctx| {
        ctx.say(format!("Renamed folder {}/{} to {}.", tool["id"].s(), folder["id"].s(), quoted(&folder["name"].s())));
        Ok(())
    })
}

fn folder_move(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "folder")?;
    let parent = folder_id(args.at(1))?;
    let folder = ctx.patch(&format!("/tools/{}/files/folders/{id}", tool["id"].s()), json!({ "parent_id": parent }))?;
    ctx.output(&folder, |ctx| {
        ctx.say(format!(
            "Moved folder {}/{} {} to {}.",
            tool["id"].s(),
            folder["id"].s(),
            quoted(&folder["name"].s()),
            place(&tool, &folder["parent_id"])
        ));
        Ok(())
    })
}

fn folder_delete(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "folder")?;
    ctx.delete(&format!("/tools/{}/files/folders/{id}", tool["id"].s()))?;
    ctx.output(&Value::Null, |ctx| {
        ctx.say(format!("Deleted folder {}/{id} and everything in it.", tool["id"].s()));
        Ok(())
    })
}

fn folder_download(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let (tool, id) = ctx.tool_and_id(args.at(0), "files", "folder")?;
    let listing = ctx.get(&format!("/tools/{}/files", tool["id"].s()), &[("folder_id", Some(id.to_string()))])?;
    let mut folder = listing["folder"].clone();

    let name = format!("{}.zip", folder["name"].s());
    let path = download(ctx, &format!("/tools/{}/files/folders/{id}/download", tool["id"].s()), &name, args)?;
    folder["path"] = json!(path);
    ctx.output(&folder, |ctx| {
        ctx.say(format!("Downloaded folder {}/{id} {} to {path}.", tool["id"].s(), quoted(&folder["name"].s())));
        Ok(())
    })
}

/// A folder id (TOOL/ID works too), or None for root: the top level.
fn folder_id(value: &str) -> Result<Option<i64>> {
    if value == "root" {
        return Ok(None);
    }
    let id = value.rsplit('/').next().unwrap_or("");
    if !is_digits(id) {
        usage!("Expected a folder id like 12, or root; got {}.", quoted(value));
    }
    Ok(Some(id.parse().unwrap_or(0)))
}

fn place(tool: &Value, folder_id: &Value) -> String {
    match folder_id.opt() {
        Some(folder) => format!("folder {}/{folder}", tool["id"].s()),
        None => "the top level".to_string(),
    }
}

/// Saves a download into the current directory under `name` (only its last
/// path segment, whatever the server sent), or to --output. Returns the path.
fn download(ctx: &mut Ctx, path: &str, name: &str, args: &Args) -> Result<String> {
    let mut name = Path::new(name).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    if name.replace(['.', '/'], "").is_empty() {
        name = "download".to_string();
    }
    let destination = match args.flag("output") {
        None => PathBuf::from(&name),
        Some(output) if Path::new(output).is_dir() => Path::new(output).join(&name),
        Some(output) => PathBuf::from(output),
    };

    let directory = match destination.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    if !directory.is_dir() {
        fail!("{} is not a directory.", directory.display());
    }
    if destination.exists() && !args.on("force") {
        fail!("{} already exists. Use --force to overwrite it.", destination.display());
    }

    ctx.api()?.download(path, &destination)?;
    Ok(destination.display().to_string())
}

fn share_summary(share: &Value) -> String {
    let details = join(
        [
            day(&share["expires_at"]).map(|at| format!("expires {at}")),
            share["password_protected"].truthy().then(|| "password protected".to_string()),
            Some(format!("downloaded {}", count(share["download_count"].int(), "time"))),
        ],
        ", ",
    );
    format!("{} ({details})", share["url"].s())
}
