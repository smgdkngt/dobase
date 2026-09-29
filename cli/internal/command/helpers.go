package command

import (
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// DateLayout is how dates are written: 2026-09-24.
const DateLayout = "2006-01-02"

// Clean strips what's printed of C0 controls except tab and newline, DEL and C1 controls.
func Clean(text string) string {
	return strings.Map(func(r rune) rune {
		if (r <= 0x08) || (r >= 0x0b && r <= 0x1f) || (r >= 0x7f && r <= 0x9f) {
			return -1
		}
		return r
	}, text)
}

// Paragraphs turns plain text into HTML paragraphs: blank lines separate them,
// single newlines become <br>.
func Paragraphs(text string) string {
	text = strings.ReplaceAll(strings.TrimSpace(text), "\r\n", "\n")
	var html strings.Builder
	for text != "" {
		paragraph, next, _ := strings.Cut(text, "\n\n")
		html.WriteString("<p>" + strings.ReplaceAll(EscapeHTML(paragraph), "\n", "<br>") + "</p>")
		text = strings.TrimLeft(next, "\n")
	}
	return html.String()
}

func EscapeHTML(text string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;", "'", "&#39;").Replace(text)
}

// Width is the length of text in characters.
func Width(text string) int { return utf8.RuneCountInString(text) }

// Ljust pads text with spaces to width characters.
func Ljust(text string, width int) string {
	if length := Width(text); length < width {
		return text + strings.Repeat(" ", width-length)
	}
	return text
}

// Quoted quotes names and titles in messages.
func Quoted(text string) string { return "\"" + text + "\"" }

// Today is the local date, as midnight UTC so adding days never meets a DST change.
func Today() time.Time {
	year, month, day := time.Now().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

// ParseDate reads YYYY-MM-DD as midnight UTC.
func ParseDate(value string) (time.Time, bool) {
	date, err := time.Parse(DateLayout, value)
	return date, err == nil && len(value) == 10
}

// DateParam reads "today", "tomorrow", "YYYY-MM-DD", or "none", which is "" (to clear).
func DateParam(value string) (string, error) {
	switch value {
	case "none":
		return "", nil
	case "today":
		return Today().Format(DateLayout), nil
	case "tomorrow":
		return Today().AddDate(0, 0, 1).Format(DateLayout), nil
	}
	date, ok := ParseDate(value)
	if !ok {
		return "", api.Usagef("Expected a date like 2026-10-01, today, tomorrow or none; got %s.", Quoted(value))
	}
	return date.Format(DateLayout), nil
}

// Person is "Name <email>", or "" for null.
func Person(user api.Value) string {
	if user.IsNull() {
		return ""
	}
	return fmt.Sprintf("%s <%s>", user.Get("name").S(), user.Get("email_address").S())
}

// Day is "2026-09-24", or "" for null.
func Day(value api.Value) string { return firstChars(value.S(), 10) }

// Moment is "2026-09-24 14:05", or "" for null.
func Moment(value api.Value) string {
	return strings.ReplaceAll(firstChars(value.S(), 16), "T", " ")
}

func firstChars(text string, n int) string {
	runes := []rune(text)
	if len(runes) > n {
		runes = runes[:n]
	}
	return string(runes)
}

// Count is "1 card", "3 cards".
func Count(number int64, noun string) string {
	if number == 1 {
		return fmt.Sprintf("%d %s", number, noun)
	}
	return fmt.Sprintf("%d %ss", number, noun)
}

// Bytes is a size for people: "512 B", "2.0 KB", "14 MB".
func Bytes(size api.Value) string {
	n := size.Int()
	if n < 1024 {
		return fmt.Sprintf("%d B", n)
	}
	value, unit := float64(n), "TB"
	for _, candidate := range []string{"KB", "MB", "GB", "TB"} {
		value /= 1024
		if value < 1024 {
			unit = candidate
			break
		}
	}
	if value < 10 {
		return fmt.Sprintf("%.1f %s", value, unit)
	}
	return fmt.Sprintf("%.0f %s", value, unit)
}

// Join joins the parts that aren't empty.
func Join(separator string, parts ...string) string {
	var kept []string
	for _, part := range parts {
		if part != "" {
			kept = append(kept, part)
		}
	}
	return strings.Join(kept, separator)
}

// If is text when condition holds, else "".
func If(condition bool, text string) string {
	if condition {
		return text
	}
	return ""
}

func IsDigits(text string) bool {
	if text == "" {
		return false
	}
	for i := 0; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	return true
}

// Compact drops the nil (and null Value) fields of a request body, which leave
// out what wasn't given.
func Compact(fields map[string]any) map[string]any {
	for key, field := range fields {
		if field == nil {
			delete(fields, key)
		} else if value, ok := field.(api.Value); ok && value.IsNull() {
			delete(fields, key)
		}
	}
	return fields
}
