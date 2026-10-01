package commands

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func fileDownloadFlags() []Flag {
	return []Flag{F("output", "PATH", "Save to PATH, or into PATH when it is a directory"), Switch("force", "Overwrite an existing file")}
}

func files() []*Definition {
	return []*Definition{
		New("file list", "List the folders and files at the top level, or in FOLDER (a folder id)", []string{"TOOL", "[FOLDER]"}, nil, listFiles),
		New("file show", "Show a file's details and its public link, if it has one", []string{"TOOL/FILE"}, nil, showFile),
		New("file upload", "Upload files (200 MB max each), to the top level unless --folder", []string{"TOOL", "PATH..."},
			[]Flag{F("folder", "FOLDER", "Folder id to upload into")}, uploadFiles),
		New("file download", "Download a file, to its own name in the current directory unless --output", []string{"TOOL/FILE"},
			fileDownloadFlags(), downloadFile),
		New("file rename", "Rename a file", []string{"TOOL/FILE", "NAME"}, nil, renameFile),
		New("file move", "Move a file into FOLDER (a folder id), or to the top level with root", []string{"TOOL/FILE", "FOLDER"}, nil, moveFile),
		New("file delete", "Delete a file permanently", []string{"TOOL/FILE"}, nil, deleteFile),
		New("folder create", "Create a folder, at the top level unless --parent", []string{"TOOL", "NAME"},
			[]Flag{F("parent", "FOLDER", "Folder id to create it in")}, createFolder),
		New("folder rename", "Rename a folder", []string{"TOOL/FOLDER", "NAME"}, nil, renameFolder),
		New("folder move", "Move a folder into PARENT (a folder id), or to the top level with root", []string{"TOOL/FOLDER", "PARENT"}, nil, moveFolder),
		New("folder delete", "Delete a folder and everything in it, permanently", []string{"TOOL/FOLDER"}, nil, deleteFolder),
		New("folder download", "Download a folder and everything in it as a zip, to FOLDER-NAME.zip unless --output", []string{"TOOL/FOLDER"},
			fileDownloadFlags(), downloadFolder),
	}
}

func listFiles(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "files")
	if err != nil {
		return err
	}
	folder := api.Null
	if len(args.Positional) > 1 {
		if folder, err = fileFolderID(args.At(1)); err != nil {
			return err
		}
	}
	listing, err := ctx.Get(fmt.Sprintf("/tools/%s/files", tool.Get("id").S()), "folder_id", folder.S())
	if err != nil {
		return err
	}

	return ctx.Output(listing, func() error {
		trail := []string{tool.Get("name").S()}
		for _, crumb := range listing.Get("breadcrumbs").Items() {
			trail = append(trail, crumb.Get("name").S())
		}
		if name := listing.Get("folder", "name"); !name.IsNull() {
			trail = append(trail, name.S())
		}
		location := "files " + tool.Get("id").S()
		if listing.Get("folder").Truthy() {
			location = fmt.Sprintf("folder %s/%s", tool.Get("id").S(), listing.Get("folder", "id").S())
		}
		ctx.Sayf("%s (%s) %s", strings.Join(trail, " / "), location, listing.Get("url").S())
		ctx.Blank()

		shared := func(entry api.Value) string { return If(entry.Get("shared").Truthy(), "shared") }
		var rows [][]string
		for _, entry := range listing.Get("folders").Items() {
			rows = append(rows, []string{fmt.Sprintf("folder %s/%s", tool.Get("id").S(), entry.Get("id").S()), entry.Get("name").S(), "", "", shared(entry)})
		}
		for _, entry := range listing.Get("files").Items() {
			rows = append(rows, []string{
				tool.Get("id").S() + "/" + entry.Get("id").S(),
				entry.Get("name").S(),
				Bytes(entry.Get("file_size")),
				Day(entry.Get("created_at")),
				shared(entry),
			})
		}
		if len(rows) == 0 {
			ctx.Say("  (empty)")
		} else {
			ctx.Table(rows, 2)
		}
		return nil
	})
}

func showFile(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "file")
	if err != nil {
		return err
	}
	file, err := ctx.Get(fmt.Sprintf("/tools/%s/files/items/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	return ctx.Output(file, func() error {
		ctx.Sayf("%s (file %s/%s)", file.Get("name").S(), tool.Get("id").S(), file.Get("id").S())
		folder := "top level"
		if !file.Get("folder_id").IsNull() {
			folder = fmt.Sprintf("folder %s/%s", tool.Get("id").S(), file.Get("folder_id").S())
		}
		ctx.Field("Folder", folder)
		ctx.Field("Type", file.Get("content_type").S())
		ctx.Field("Size", Bytes(file.Get("file_size")))
		ctx.Field("Created", Join(" by ", Moment(file.Get("created_at")), file.Get("creator", "name").S()))
		ctx.Field("URL", file.Get("url").S())
		ctx.Field("Download", file.Get("download_url").S())
		if file.Get("share").Truthy() {
			ctx.Field("Shared", shareSummary(file.Get("share")))
		}
		return nil
	})
}

func uploadFiles(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "files")
	if err != nil {
		return err
	}
	paths := args.Rest(1)
	for _, path := range paths {
		if info, err := os.Stat(path); err != nil || !info.Mode().IsRegular() {
			return api.Failf("%s is not a file.", path)
		}
	}
	var fields []api.Param
	if value, ok := args.Flag("folder"); ok {
		folder, err := fileFolderID(value)
		if err != nil {
			return err
		}
		if !folder.IsNull() {
			fields = append(fields, api.Param{Name: "folder_id", Value: folder.S()})
		}
	}

	parts := make([]api.FilePart, len(paths))
	for i, path := range paths {
		parts[i] = api.FilePart{Field: "files[]", Path: path}
	}
	server, err := ctx.API()
	if err != nil {
		return err
	}
	uploaded, err := server.Upload(fmt.Sprintf("/tools/%s/files/uploads", tool.Get("id").S()), parts, fields)
	if err != nil {
		return err
	}
	return ctx.Output(uploaded, func() error {
		for _, file := range uploaded.Items() {
			ctx.Sayf("Uploaded %s (%s) to %s as %s/%s.", file.Get("name").S(), Bytes(file.Get("file_size")),
				folderPlace(tool, file.Get("folder_id")), tool.Get("id").S(), file.Get("id").S())
		}
		return nil
	})
}

func downloadFile(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "file")
	if err != nil {
		return err
	}
	file, err := ctx.Get(fmt.Sprintf("/tools/%s/files/items/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	path, err := saveDownload(ctx, fmt.Sprintf("/tools/%s/files/items/%d/download", tool.Get("id").S(), id), file.Get("name").S(), file.Get("file_size"), args)
	if err != nil {
		return err
	}
	file = file.With("path", path)
	return ctx.Output(file, func() error {
		ctx.Sayf("Downloaded %s (%s) to %s.", file.Get("name").S(), Bytes(file.Get("file_size")), path)
		return nil
	})
}

func renameFile(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "file")
	if err != nil {
		return err
	}
	file, err := ctx.Patch(fmt.Sprintf("/tools/%s/files/items/%d", tool.Get("id").S(), id), map[string]any{"name": args.At(1)})
	if err != nil {
		return err
	}
	return ctx.Output(file, func() error {
		ctx.Sayf("Renamed file %s/%s to %s.", tool.Get("id").S(), file.Get("id").S(), Quoted(file.Get("name").S()))
		return nil
	})
}

func moveFile(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "file")
	if err != nil {
		return err
	}
	folder, err := fileFolderID(args.At(1))
	if err != nil {
		return err
	}
	file, err := ctx.Patch(fmt.Sprintf("/tools/%s/files/items/%d", tool.Get("id").S(), id), map[string]any{"folder_id": folder})
	if err != nil {
		return err
	}
	return ctx.Output(file, func() error {
		ctx.Sayf("Moved file %s/%s %s to %s.", tool.Get("id").S(), file.Get("id").S(), Quoted(file.Get("name").S()), folderPlace(tool, file.Get("folder_id")))
		return nil
	})
}

func deleteFile(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "file")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/files/items/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted file %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func createFolder(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "files")
	if err != nil {
		return err
	}
	parent := api.Null
	if value, ok := args.Flag("parent"); ok {
		if parent, err = fileFolderID(value); err != nil {
			return err
		}
	}
	folder, err := ctx.Post(fmt.Sprintf("/tools/%s/files/folders", tool.Get("id").S()), Compact(map[string]any{"name": args.At(1), "parent_id": parent}))
	if err != nil {
		return err
	}

	location := "at the top level"
	if folder.Get("parent_id").Truthy() {
		location = "in " + folderPlace(tool, folder.Get("parent_id"))
	}
	return ctx.Output(folder, func() error {
		ctx.Sayf("Created folder %s/%s %s %s: %s", tool.Get("id").S(), folder.Get("id").S(), Quoted(folder.Get("name").S()), location, folder.Get("url").S())
		return nil
	})
}

func renameFolder(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "folder")
	if err != nil {
		return err
	}
	folder, err := ctx.Patch(fmt.Sprintf("/tools/%s/files/folders/%d", tool.Get("id").S(), id), map[string]any{"name": args.At(1)})
	if err != nil {
		return err
	}
	return ctx.Output(folder, func() error {
		ctx.Sayf("Renamed folder %s/%s to %s.", tool.Get("id").S(), folder.Get("id").S(), Quoted(folder.Get("name").S()))
		return nil
	})
}

func moveFolder(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "folder")
	if err != nil {
		return err
	}
	parent, err := fileFolderID(args.At(1))
	if err != nil {
		return err
	}
	folder, err := ctx.Patch(fmt.Sprintf("/tools/%s/files/folders/%d", tool.Get("id").S(), id), map[string]any{"parent_id": parent})
	if err != nil {
		return err
	}
	return ctx.Output(folder, func() error {
		ctx.Sayf("Moved folder %s/%s %s to %s.", tool.Get("id").S(), folder.Get("id").S(), Quoted(folder.Get("name").S()), folderPlace(tool, folder.Get("parent_id")))
		return nil
	})
}

func deleteFolder(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "folder")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/files/folders/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted folder %s/%d and everything in it.", tool.Get("id").S(), id)
		return nil
	})
}

func downloadFolder(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "files", "folder")
	if err != nil {
		return err
	}
	listing, err := ctx.Get(fmt.Sprintf("/tools/%s/files", tool.Get("id").S()), "folder_id", strconv.FormatInt(id, 10))
	if err != nil {
		return err
	}
	folder := listing.Get("folder")

	name := folder.Get("name").S() + ".zip"
	// A zip is made as it's sent, so nothing says how big it will be.
	path, err := saveDownload(ctx, fmt.Sprintf("/tools/%s/files/folders/%d/download", tool.Get("id").S(), id), name, api.Null, args)
	if err != nil {
		return err
	}
	folder = folder.With("path", path)
	return ctx.Output(folder, func() error {
		ctx.Sayf("Downloaded folder %s/%d %s to %s.", tool.Get("id").S(), id, Quoted(folder.Get("name").S()), path)
		return nil
	})
}

// fileFolderID is a folder id (TOOL/ID works too), or null for root: the top level.
func fileFolderID(value string) (api.Value, error) {
	if value == "root" {
		return api.Null, nil
	}
	id := value[strings.LastIndex(value, "/")+1:]
	if !IsDigits(id) {
		return api.Null, api.Usagef("Expected a folder id like 12, or root; got %s.", Quoted(value))
	}
	number, _ := strconv.ParseInt(id, 10, 64)
	return api.Of(number), nil
}

func folderPlace(tool, folderID api.Value) string {
	if folderID.IsNull() {
		return "the top level"
	}
	return fmt.Sprintf("folder %s/%s", tool.Get("id").S(), folderID.S())
}

// saveDownload saves a download into the current directory under name (only its
// last path segment, whatever the server sent), or to --output. It returns the
// path. size is how big the file should be, or null when nothing says.
func saveDownload(ctx *Ctx, path, name string, size api.Value, args *Args) (string, error) {
	name = lastSegment(name)
	if strings.NewReplacer(".", "", "/", "").Replace(name) == "" {
		name = "download"
	}
	destination := name
	if output, ok := args.Flag("output"); ok {
		destination = output
		if info, err := os.Stat(output); err == nil && info.IsDir() {
			destination = strings.TrimSuffix(output, "/") + "/" + name
		}
	}

	directory := parentDirectory(destination)
	if info, err := os.Stat(directory); err != nil || !info.IsDir() {
		return "", api.Failf("%s is not a directory.", directory)
	}
	if _, err := os.Stat(destination); err == nil && !args.On("force") {
		return "", api.Failf("%s already exists. Use --force to overwrite it.", destination)
	}

	server, err := ctx.API()
	if err != nil {
		return "", err
	}
	if _, err := api.DownloadWhole(server, path, destination, size); err != nil {
		return "", err
	}
	return destination, nil
}

// lastSegment is the last part of a path that names something ("" when that's
// ".."), skipping empty and "." parts, like Rust's Path::file_name.
func lastSegment(path string) string {
	last := ""
	for _, part := range strings.Split(path, "/") {
		if part != "" && part != "." {
			last = part
		}
	}
	if last == ".." {
		return ""
	}
	return last
}

// parentDirectory is the directory a path is in, written as in the path
// (like Rust's Path::parent): "." for a bare name.
func parentDirectory(path string) string {
	rest := trimTrailing(path)
	index := strings.LastIndex(rest, "/")
	if index < 0 {
		return "."
	}
	if parent := trimTrailing(rest[:index]); parent != "" {
		return parent
	}
	return "/"
}

// trimTrailing drops trailing slashes and "." parts: "a/./" is "a".
func trimTrailing(path string) string {
	for {
		trimmed := strings.TrimRight(path, "/")
		if !strings.HasSuffix(trimmed, "/.") {
			return trimmed
		}
		path = strings.TrimSuffix(trimmed, ".")
	}
}

func shareSummary(share api.Value) string {
	details := Join(", ",
		If(!share.Get("expires_at").IsNull(), "expires "+Day(share.Get("expires_at"))),
		If(share.Get("password_protected").Truthy(), "password protected"),
		"downloaded "+Count(share.Get("download_count").Int(), "time"),
	)
	return fmt.Sprintf("%s (%s)", share.Get("url").S(), details)
}
