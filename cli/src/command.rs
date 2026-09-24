//! What every command shares: its definition (name, arguments, flags), the
//! parsed arguments, and a context with the helpers commands are written in:
//! API calls, lookups, input parsing and output.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::Path;

use jiff::civil::Date;
use serde_json::Value;

use crate::client::{Api, Client, Method};
use crate::config::Config;
use crate::value::{Json, is_digits};

// -- Errors ------------------------------------------------------------------

#[derive(Debug)]
pub enum Error {
    /// Wrong arguments: exits with 2.
    Usage(String),
    /// Anything else that went wrong: exits with 1.
    Failed(String),
    /// `--help` on a command: its usage, printed to stdout.
    Help(String),
}

impl Error {
    pub fn usage(message: impl Into<String>) -> Self {
        Self::Usage(message.into())
    }

    pub fn failed(message: impl Into<String>) -> Self {
        Self::Failed(message.into())
    }

    pub fn io(path: &Path, error: std::io::Error) -> Self {
        Self::Failed(format!("{}: {}", path.display(), error))
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// Returns early with a usage error.
macro_rules! usage {
    ($($message:tt)*) => { return Err($crate::command::Error::usage(format!($($message)*))) };
}

/// Returns early with an error.
macro_rules! fail {
    ($($message:tt)*) => { return Err($crate::command::Error::failed(format!($($message)*))) };
}

pub(crate) use {fail, usage};

// -- Definitions -------------------------------------------------------------

pub type Run = fn(&mut Ctx<'_>, &Args) -> Result<()>;

#[derive(Clone)]
pub struct Flag {
    pub name: &'static str,
    /// Flags with a placeholder take a value; flags without one are switches.
    pub placeholder: Option<&'static str>,
    pub description: String,
}

/// `--name VALUE`
pub fn flag(name: &'static str, placeholder: &'static str, description: impl Into<String>) -> Flag {
    Flag { name, placeholder: Some(placeholder), description: description.into() }
}

/// `--name`
pub fn switch(name: &'static str, description: impl Into<String>) -> Flag {
    Flag { name, placeholder: None, description: description.into() }
}

pub struct Definition {
    pub name: &'static str,
    pub summary: String,
    pub args: Vec<&'static str>,
    pub flags: Vec<Flag>,
    pub run: Run,
}

/// command("card create", "Add a card", &["TOOL", "TITLE"], vec![flag(..), switch(..)], run)
pub fn command(name: &'static str, summary: impl Into<String>, args: &[&'static str], flags: Vec<Flag>, run: Run) -> Definition {
    Definition { name, summary: summary.into(), args: args.to_vec(), flags, run }
}

impl Definition {
    pub fn usage(&self) -> String {
        std::iter::once("dobase").chain(std::iter::once(self.name)).chain(self.args.iter().copied()).collect::<Vec<_>>().join(" ")
    }

    pub fn noun(&self) -> Option<&'static str> {
        self.name.split_once(' ').map(|(noun, _)| noun)
    }

    fn min_args(&self) -> usize {
        self.args.iter().filter(|arg| !arg.starts_with('[')).count()
    }

    fn max_args(&self) -> usize {
        if self.args.iter().any(|arg| arg.ends_with("...")) { usize::MAX } else { self.args.len() }
    }

    /// `--flag VALUE` as shown in help.
    pub fn flag_label(flag: &Flag) -> String {
        match flag.placeholder {
            Some(placeholder) => format!("--{} {placeholder}", flag.name),
            None => format!("--{}", flag.name),
        }
    }

    pub fn help(&self) -> String {
        let mut help = format!("Usage: {}\n\n{}\n", self.usage(), self.summary);
        if !self.flags.is_empty() {
            help.push('\n');
        }
        for flag in &self.flags {
            // Laid out like Ruby's OptionParser, which the first version of the CLI used.
            let label = format!("    {}", Self::flag_label(flag));
            if label.chars().count() > 32 {
                help.push_str(&format!("    {label}\n    {:32} {}\n", "", flag.description));
            } else {
                help.push_str(&format!("    {} {}\n", ljust(&label, 32), flag.description));
            }
        }
        help
    }

    /// Splits `argv` into positional arguments and flags, which may come in any order.
    pub fn parse(&self, argv: &[String]) -> Result<Args> {
        let mut args = Args::default();
        let mut words = argv.iter();

        while let Some(word) = words.next() {
            if word == "--" {
                args.positional.extend(words.by_ref().cloned());
                break;
            }
            if word == "--help" || word == "-h" {
                return Err(Error::Help(self.help()));
            }
            if !word.starts_with('-') || word == "-" {
                args.positional.push(word.clone());
                continue;
            }

            let (name, inline) = match word.split_once('=') {
                Some((name, value)) => (name, Some(value.to_string())),
                None => (word.as_str(), None),
            };
            let Some(flag) = name.strip_prefix("--").and_then(|name| self.flags.iter().find(|flag| flag.name == name)) else {
                usage!("invalid option: {word}\n\n{}", self.help());
            };

            if flag.placeholder.is_some() {
                let value = match inline {
                    Some(value) => value,
                    None => match words.next() {
                        Some(value) => value.clone(),
                        None => usage!("missing argument: {name}\n\n{}", self.help()),
                    },
                };
                args.values.insert(flag.name, value);
            } else if inline.is_some() {
                usage!("needless argument: {word}\n\n{}", self.help());
            } else {
                args.values.insert(flag.name, String::new());
            }
        }

        if args.positional.len() < self.min_args() || args.positional.len() > self.max_args() {
            return Err(Error::Usage(self.help()));
        }
        Ok(args)
    }
}

#[derive(Default, Debug)]
pub struct Args {
    pub positional: Vec<String>,
    values: HashMap<&'static str, String>,
}

impl Args {
    /// A required positional argument.
    pub fn at(&self, index: usize) -> &str {
        &self.positional[index]
    }

    /// An optional positional argument.
    pub fn get(&self, index: usize) -> Option<&str> {
        self.positional.get(index).map(String::as_str)
    }

    /// The positional arguments from `index` on, for `PATH...`.
    pub fn rest(&self, index: usize) -> &[String] {
        self.positional.get(index..).unwrap_or(&[])
    }

    /// The value of a `--name VALUE` flag.
    pub fn flag(&self, name: &str) -> Option<&str> {
        self.values.get(name).map(String::as_str)
    }

    /// Whether a `--name` switch was given.
    pub fn on(&self, name: &str) -> bool {
        self.values.contains_key(name)
    }

    /// Whether any of these flags or switches was given.
    pub fn any(&self, names: &[&str]) -> bool {
        names.iter().any(|name| self.values.contains_key(name))
    }
}

// -- Context -----------------------------------------------------------------

pub struct Ctx<'a> {
    pub config: Config,
    out: &'a mut dyn Write,
    json: bool,
    pub user_agent: String,
    api: Option<Box<dyn Api>>,
    me: Option<Value>,
    tools: Option<Vec<Value>>,
}

impl<'a> Ctx<'a> {
    pub fn new(config: Config, out: &'a mut dyn Write, json: bool, user_agent: String) -> Self {
        Self { config, out, json, user_agent, api: None, me: None, tools: None }
    }

    /// Talks to `api` instead of the configured server.
    pub fn set_api(&mut self, api: Box<dyn Api>) {
        self.api = Some(api);
        self.me = None;
        self.tools = None;
    }

    // -- API -----------------------------------------------------------------

    pub fn api(&mut self) -> Result<&mut dyn Api> {
        if self.api.is_none() {
            let client = Client::new(self.config.url(), self.config.token(), &self.user_agent)?;
            self.api = Some(Box::new(client));
        }
        Ok(self.api.as_deref_mut().unwrap())
    }

    /// GET with query parameters; the ones that are None are left out.
    pub fn get(&mut self, path: &str, params: &[(&str, Option<String>)]) -> Result<Value> {
        let params: Vec<(&str, String)> = params.iter().filter_map(|(name, value)| value.clone().map(|value| (*name, value))).collect();
        self.api()?.request(Method::Get, path, &params, &Value::Null)
    }

    pub fn post(&mut self, path: &str, body: Value) -> Result<Value> {
        self.api()?.request(Method::Post, path, &[], &body)
    }

    pub fn patch(&mut self, path: &str, body: Value) -> Result<Value> {
        self.api()?.request(Method::Patch, path, &[], &body)
    }

    pub fn delete(&mut self, path: &str) -> Result<Value> {
        self.api()?.request(Method::Delete, path, &[], &Value::Null)
    }

    pub fn me(&mut self) -> Result<Value> {
        if self.me.is_none() {
            self.me = Some(self.get("/profile", &[])?);
        }
        Ok(self.me.clone().unwrap())
    }

    // -- Lookups -------------------------------------------------------------

    /// Finds a tool by id or (part of) its name. With a type, only tools of that
    /// type count, so "launch" finds the one todos tool among several "Launch" tools.
    pub fn tool(&mut self, reference: &str, kind: Option<&str>) -> Result<Value> {
        if self.tools.is_none() {
            self.tools = Some(self.get("/tools", &[])?.items().to_vec());
        }
        let tools = self.tools.as_ref().unwrap();
        let of_kind: Vec<Value> = tools.iter().filter(|tool| kind.is_none_or(|kind| tool["type"].s() == kind)).cloned().collect();
        let matches = matching_tools(&of_kind, reference);

        if matches.is_empty() {
            let other = matching_tools(tools, reference);
            if let (Some(kind), [other]) = (kind, other.as_slice()) {
                fail!("{} ({}) is a {} tool, not {kind}.", other["name"].s(), other["id"].s(), other["type"].s());
            }
            let kind = kind.map(|kind| format!("{kind} ")).unwrap_or_default();
            fail!("No {kind}tool matches {}. Run `dobase tool list`.", quoted(reference));
        }
        if matches.len() > 1 {
            let names: Vec<String> = matches.iter().map(|tool| format!("{} ({})", tool["name"].s(), tool["id"].s())).collect();
            fail!("{} matches several tools: {}", quoted(reference), names.join(", "));
        }
        Ok(matches.into_iter().next().unwrap())
    }

    /// Splits "TOOL/ID" (e.g. "12/104" or "Roadmap/104") into a tool and a numeric id.
    pub fn tool_and_id(&mut self, reference: &str, kind: &str, what: &str) -> Result<(Value, i64)> {
        match reference.rsplit_once('/') {
            Some((tool, id)) if !tool.is_empty() && is_digits(id) => Ok((self.tool(tool, Some(kind))?, id.parse().unwrap_or(0))),
            _ => usage!("Expected TOOL/{} like 12/104, got {}.", what.to_uppercase(), quoted(reference)),
        }
    }

    /// Resolves "me", "none", a user id, an email address or part of a name to a
    /// collaborator id on `tool`. "none" is null (unassigned).
    pub fn user_id(&mut self, tool: &Value, value: &str) -> Result<Value> {
        if value == "none" {
            return Ok(Value::Null);
        }
        if value == "me" {
            return Ok(self.me()?["id"].clone());
        }
        if is_digits(value) {
            return Ok(Value::from(value.parse::<i64>().unwrap_or(0)));
        }

        let details = self.get(&format!("/tools/{}", tool["id"].s()), &[])?;
        let collaborators = details["collaborators"].items();
        let mut matches: Vec<&Value> = collaborators.iter().filter(|user| user["email_address"].s().eq_ignore_ascii_case(value)).collect();
        if matches.is_empty() {
            let needle = value.to_lowercase();
            matches = collaborators.iter().filter(|user| user["name"].s().to_lowercase().contains(&needle)).collect();
        }

        match matches.as_slice() {
            [] => fail!("Nobody on {} matches {}.", tool["name"].s(), quoted(value)),
            [user] => Ok(user["id"].clone()),
            _ => {
                let names: Vec<String> = matches.iter().map(|user| user["name"].s()).collect();
                fail!("{} matches several people: {}", quoted(value), names.join(", "))
            }
        }
    }

    // -- Input ---------------------------------------------------------------

    /// A text argument of "-" is read from stdin, so long text can come from a heredoc or file.
    pub fn text(&self, value: &str) -> Result<String> {
        if value != "-" {
            return Ok(value.to_string());
        }
        let mut bytes = Vec::new();
        std::io::stdin().read_to_end(&mut bytes).map_err(|error| Error::failed(format!("Could not read stdin: {error}")))?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }

    /// Plain text becomes paragraphs; with `html` the text is passed through as HTML.
    pub fn rich_text(&self, value: &str, html: bool) -> Result<String> {
        let value = self.text(value)?;
        Ok(if html { value } else { paragraphs(&value) })
    }

    // -- Output --------------------------------------------------------------

    /// Prints `data` as JSON with --json, otherwise runs `text` to print it for people.
    pub fn output(&mut self, data: &Value, text: impl FnOnce(&mut Self) -> Result<()>) -> Result<()> {
        if self.json {
            let json = serde_json::to_string_pretty(data).unwrap();
            let _ = writeln!(self.out, "{json}");
            Ok(())
        } else {
            text(self)
        }
    }

    /// Prints a line. Text from the server is written by other people, so control
    /// characters go (escape sequences could rewrite the terminal); newlines and tabs stay.
    pub fn say(&mut self, line: impl AsRef<str>) {
        let _ = writeln!(self.out, "{}", clean(line.as_ref()));
    }

    pub fn blank(&mut self) {
        self.say("");
    }

    pub fn table(&mut self, rows: Vec<Vec<String>>, indent: usize) {
        let Some(first) = rows.first() else { return };
        let widths: Vec<usize> =
            (0..first.len()).map(|column| rows.iter().map(|row| row[column].chars().count()).max().unwrap_or(0)).collect();

        for row in &rows {
            let cells: Vec<String> = row
                .iter()
                .enumerate()
                .map(|(index, cell)| if index == row.len() - 1 { cell.clone() } else { ljust(cell, widths[index]) })
                .collect();
            let line = format!("{}{}", " ".repeat(indent), cells.join("  "));
            self.say(line.trim_end());
        }
    }

    /// "Label:    value", unless there's no value.
    pub fn field(&mut self, label: &str, value: impl Into<Option<String>>) {
        if let Some(value) = value.into().filter(|value| !value.is_empty()) {
            self.say(format!("{} {value}", ljust(&format!("{label}:"), 11)));
        }
    }

    pub fn paragraph(&mut self, text: &str, indent: usize) {
        for line in text.trim().split_inclusive('\n') {
            if line.trim().is_empty() {
                self.say("");
            } else {
                self.say(format!("{}{}", " ".repeat(indent), line.trim_end()));
            }
        }
    }
}

fn matching_tools(tools: &[Value], reference: &str) -> Vec<Value> {
    if is_digits(reference) {
        let id: i64 = reference.parse().unwrap_or(-1);
        return tools.iter().filter(|tool| tool["id"].int() == id).cloned().collect();
    }

    let exact: Vec<Value> = tools.iter().filter(|tool| tool["name"].s().to_lowercase() == reference.to_lowercase()).cloned().collect();
    if !exact.is_empty() {
        return exact;
    }
    let needle = reference.to_lowercase();
    tools.iter().filter(|tool| tool["name"].s().to_lowercase().contains(&needle)).cloned().collect()
}

// -- Helpers -----------------------------------------------------------------

/// Characters stripped from what's printed: C0 controls except tab and newline, DEL and C1 controls.
pub fn clean(text: &str) -> String {
    text.chars().filter(|&char| !matches!(char, '\u{0}'..='\u{8}' | '\u{b}'..='\u{1f}' | '\u{7f}'..='\u{9f}')).collect()
}

pub fn paragraphs(text: &str) -> String {
    let text = text.trim().replace("\r\n", "\n");
    let mut html = String::new();
    let mut rest = text.as_str();
    while !rest.is_empty() {
        let (paragraph, next) = match rest.find("\n\n") {
            Some(index) => (&rest[..index], rest[index..].trim_start_matches('\n')),
            None => (rest, ""),
        };
        html.push_str(&format!("<p>{}</p>", escape_html(paragraph).replace('\n', "<br>")));
        rest = next;
    }
    html
}

pub fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&#39;")
}

pub fn ljust(text: &str, width: usize) -> String {
    let length = text.chars().count();
    if length >= width { text.to_string() } else { format!("{text}{}", " ".repeat(width - length)) }
}

/// Quotes names and titles in messages.
pub fn quoted(text: &str) -> String {
    format!("\"{text}\"")
}

pub fn today() -> Date {
    jiff::Zoned::now().date()
}

/// "today", "tomorrow", "YYYY-MM-DD", or "none" (None) to clear.
pub fn date_param(value: &str) -> Result<Option<String>> {
    let date = match value {
        "none" => return Ok(None),
        "today" => today(),
        "tomorrow" => today().tomorrow().unwrap(),
        _ => value
            .parse::<Date>()
            .ok()
            .filter(|_| value.len() == 10)
            .ok_or_else(|| Error::usage(format!("Expected a date like 2026-10-01, today, tomorrow or none; got {}.", quoted(value))))?,
    };
    Ok(Some(date.to_string()))
}

pub fn person(user: &Value) -> Option<String> {
    (!user.is_null()).then(|| format!("{} <{}>", user["name"].s(), user["email_address"].s()))
}

/// "2026-09-24"
pub fn day(value: &Value) -> Option<String> {
    value.opt().map(|value| value.chars().take(10).collect())
}

/// "2026-09-24 14:05"
pub fn moment(value: &Value) -> Option<String> {
    value.opt().map(|value| value.chars().take(16).collect::<String>().replace('T', " "))
}

pub fn count(number: i64, noun: &str) -> String {
    format!("{number} {noun}{}", if number == 1 { "" } else { "s" })
}

pub fn bytes(size: &Value) -> String {
    let size = size.int();
    if size < 1024 {
        return format!("{size} B");
    }

    let mut value = size as f64;
    let mut unit = "TB";
    for candidate in ["KB", "MB", "GB", "TB"] {
        value /= 1024.0;
        if value < 1024.0 {
            unit = candidate;
            break;
        }
    }
    if value < 10.0 { format!("{value:.1} {unit}") } else { format!("{value:.0} {unit}") }
}
