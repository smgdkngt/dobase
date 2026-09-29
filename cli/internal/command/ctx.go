package command

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"unicode"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// Ctx is what a command runs in.
type Ctx struct {
	Config    *config.Config
	Out       io.Writer
	JSON      bool
	UserAgent string
	// Browser opens a URL; OpenInBrowser unless a test swaps it.
	Browser func(url string) error
	// Stdin is where a TEXT of "-" is read from.
	Stdin io.Reader

	api   api.API
	me    *api.Value
	tools []api.Value
}

func NewCtx(cfg *config.Config, out io.Writer, json bool, userAgent string) *Ctx {
	return &Ctx{Config: cfg, Out: out, JSON: json, UserAgent: userAgent, Browser: OpenInBrowser, Stdin: os.Stdin}
}

// SetAPI talks to a instead of the configured server.
func (c *Ctx) SetAPI(a api.API) {
	c.api = a
	c.me = nil
	c.tools = nil
}

// -- API ------------------------------------------------------------------------

// API is the server, connected on first use.
func (c *Ctx) API() (api.API, error) {
	if c.api == nil {
		client, err := api.NewClient(c.Config.URL(), c.Config.Token(), c.UserAgent)
		if err != nil {
			return nil, err
		}
		c.api = client
	}
	return c.api, nil
}

// Get is a GET with query parameters as name, value pairs; empty values are left out.
func (c *Ctx) Get(path string, params ...string) (api.Value, error) {
	var query []api.Param
	for i := 0; i+1 < len(params); i += 2 {
		if params[i+1] != "" {
			query = append(query, api.Param{Name: params[i], Value: params[i+1]})
		}
	}
	return c.request(api.Get, path, query, nil)
}

func (c *Ctx) Post(path string, body any) (api.Value, error) {
	return c.request(api.Post, path, nil, body)
}

func (c *Ctx) Patch(path string, body any) (api.Value, error) {
	return c.request(api.Patch, path, nil, body)
}

func (c *Ctx) Delete(path string) (api.Value, error) {
	return c.request(api.Delete, path, nil, nil)
}

func (c *Ctx) request(method api.Method, path string, params []api.Param, body any) (api.Value, error) {
	server, err := c.API()
	if err != nil {
		return api.Null, err
	}
	return server.Request(method, path, params, body)
}

// Me is the signed-in user's profile.
func (c *Ctx) Me() (api.Value, error) {
	if c.me == nil {
		profile, err := c.Get("/profile")
		if err != nil {
			return api.Null, err
		}
		c.me = &profile
	}
	return *c.me, nil
}

// -- Lookups --------------------------------------------------------------------

// Tool finds a tool by id or (part of) its name. With a kind, only tools of that
// kind count, so "launch" finds the one todos tool among several "Launch" tools.
func (c *Ctx) Tool(reference, kind string) (api.Value, error) {
	if c.tools == nil {
		tools, err := c.Get("/tools")
		if err != nil {
			return api.Null, err
		}
		c.tools = append([]api.Value{}, tools.Items()...)
	}
	var ofKind []api.Value
	for _, tool := range c.tools {
		if kind == "" || tool.Get("type").S() == kind {
			ofKind = append(ofKind, tool)
		}
	}
	matches := matchingTools(ofKind, reference)

	if len(matches) == 0 {
		other := matchingTools(c.tools, reference)
		if kind != "" && len(other) == 1 {
			return api.Null, api.Failf("%s (%s) is a %s tool, not %s.", other[0].Get("name").S(), other[0].Get("id").S(), other[0].Get("type").S(), kind)
		}
		if kind != "" {
			kind += " "
		}
		return api.Null, api.Failf("No %stool matches %s. Run `dobase tool list`.", kind, Quoted(reference))
	}
	if len(matches) > 1 {
		names := make([]string, len(matches))
		for i, tool := range matches {
			names[i] = fmt.Sprintf("%s (%s)", tool.Get("name").S(), tool.Get("id").S())
		}
		return api.Null, api.Failf("%s matches several tools: %s", Quoted(reference), strings.Join(names, ", "))
	}
	return matches[0], nil
}

// ToolAndID splits "TOOL/ID" (e.g. "12/104" or "Roadmap/104") into a tool and a numeric id.
func (c *Ctx) ToolAndID(reference, kind, what string) (api.Value, int64, error) {
	index := strings.LastIndex(reference, "/")
	if index > 0 && IsDigits(reference[index+1:]) {
		tool, err := c.Tool(reference[:index], kind)
		if err != nil {
			return api.Null, 0, err
		}
		id, _ := strconv.ParseInt(reference[index+1:], 10, 64)
		return tool, id, nil
	}
	return api.Null, 0, api.Usagef("Expected TOOL/%s like 12/104, got %s.", strings.ToUpper(what), Quoted(reference))
}

// UserID resolves "me", "none", a user id, an email address or part of a name
// to a collaborator id on tool. "none" is null (unassigned).
func (c *Ctx) UserID(tool api.Value, value string) (api.Value, error) {
	switch {
	case value == "none":
		return api.Null, nil
	case value == "me":
		me, err := c.Me()
		return me.Get("id"), err
	case IsDigits(value):
		id, _ := strconv.ParseInt(value, 10, 64)
		return api.Of(id), nil
	}

	details, err := c.Get("/tools/" + tool.Get("id").S())
	if err != nil {
		return api.Null, err
	}
	collaborators := details.Get("collaborators").Items()
	var matches []api.Value
	for _, user := range collaborators {
		if strings.EqualFold(user.Get("email_address").S(), value) {
			matches = append(matches, user)
		}
	}
	if len(matches) == 0 {
		needle := strings.ToLower(value)
		for _, user := range collaborators {
			if strings.Contains(strings.ToLower(user.Get("name").S()), needle) {
				matches = append(matches, user)
			}
		}
	}

	switch len(matches) {
	case 0:
		return api.Null, api.Failf("Nobody on %s matches %s.", tool.Get("name").S(), Quoted(value))
	case 1:
		return matches[0].Get("id"), nil
	}
	names := make([]string, len(matches))
	for i, user := range matches {
		names[i] = user.Get("name").S()
	}
	return api.Null, api.Failf("%s matches several people: %s", Quoted(value), strings.Join(names, ", "))
}

func matchingTools(tools []api.Value, reference string) []api.Value {
	var matches []api.Value
	if IsDigits(reference) {
		id, _ := strconv.ParseInt(reference, 10, 64)
		for _, tool := range tools {
			if tool.Get("id").Int() == id {
				matches = append(matches, tool)
			}
		}
		return matches
	}

	needle := strings.ToLower(reference)
	for _, tool := range tools {
		if strings.ToLower(tool.Get("name").S()) == needle {
			matches = append(matches, tool)
		}
	}
	if len(matches) > 0 {
		return matches
	}
	for _, tool := range tools {
		if strings.Contains(strings.ToLower(tool.Get("name").S()), needle) {
			matches = append(matches, tool)
		}
	}
	return matches
}

// -- Input ----------------------------------------------------------------------

// Text reads a text argument of "-" from stdin, so long text can come from a heredoc or file.
func (c *Ctx) Text(value string) (string, error) {
	if value != "-" {
		return value, nil
	}
	data, err := io.ReadAll(c.Stdin)
	if err != nil {
		return "", api.Failf("Could not read stdin: %v", err)
	}
	return strings.ToValidUTF8(string(data), "�"), nil
}

// RichText turns plain text into paragraphs; with html the text is passed through as HTML.
func (c *Ctx) RichText(value string, html bool) (string, error) {
	text, err := c.Text(value)
	if err != nil || html {
		return text, err
	}
	return Paragraphs(text), nil
}

// -- Output ---------------------------------------------------------------------

// Output prints data as JSON with --json, otherwise runs text to print it for people.
func (c *Ctx) Output(data api.Value, text func() error) error {
	if c.JSON {
		fmt.Fprintln(c.Out, data.Pretty())
		return nil
	}
	return text()
}

// Say prints a line. Text from the server is written by other people, so control
// characters go (escape sequences could rewrite the terminal); newlines and tabs stay.
func (c *Ctx) Say(line string) {
	fmt.Fprintln(c.Out, Clean(line))
}

// Sayf is Say with formatting.
func (c *Ctx) Sayf(format string, args ...any) {
	c.Say(fmt.Sprintf(format, args...))
}

func (c *Ctx) Blank() { c.Say("") }

// Table prints rows in aligned columns; the last column isn't padded.
func (c *Ctx) Table(rows [][]string, indent int) {
	if len(rows) == 0 {
		return
	}
	widths := make([]int, len(rows[0]))
	for _, row := range rows {
		for column, cell := range row {
			widths[column] = max(widths[column], Width(cell))
		}
	}
	for _, row := range rows {
		cells := make([]string, len(row))
		for index, cell := range row {
			if index == len(row)-1 {
				cells[index] = cell
			} else {
				cells[index] = Ljust(cell, widths[index])
			}
		}
		c.Say(strings.TrimRightFunc(strings.Repeat(" ", indent)+strings.Join(cells, "  "), unicode.IsSpace))
	}
}

// Field prints "Label:    value", unless there's no value.
func (c *Ctx) Field(label, value string) {
	if value != "" {
		c.Say(Ljust(label+":", 11) + " " + value)
	}
}

// Paragraph prints text indented, keeping its blank lines.
func (c *Ctx) Paragraph(text string, indent int) {
	for _, line := range strings.SplitAfter(strings.TrimSpace(text), "\n") {
		if strings.TrimSpace(line) == "" {
			c.Say("")
		} else {
			c.Say(strings.Repeat(" ", indent) + strings.TrimRightFunc(line, unicode.IsSpace))
		}
	}
}

// OpenInBrowser opens url in the default browser, or the installed Dobase app when it
// handles the link: `open` on macOS, `start` on Windows, `xdg-open` elsewhere.
func OpenInBrowser(url string) error {
	opener, args := "xdg-open", []string{url}
	switch runtime.GOOS {
	case "darwin":
		opener = "open"
	case "windows":
		opener, args = "cmd", []string{"/C", "start", "", url}
	}
	if err := exec.Command(opener, args...).Run(); err != nil {
		return fmt.Errorf("%s: %w", opener, err)
	}
	return nil
}
