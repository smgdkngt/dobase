//! The app's state, and how keys, jobs and drawing fit together.
//!
//! Screens never call the API from a key press directly: they queue a job, the
//! loop draws a spinner, then runs it. So the screen always shows what's going on.

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::time::{Duration, Instant};

use ratatui::Frame;
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use serde_json::Value;

use super::popups::{self, Popup};
use super::screens::{self, Screen, View};
use super::theme;
use super::widgets::{self, Confetti};
use crate::client::{Api, Client, Method};
use crate::command::{Error, Result};
use crate::value::Json;

/// Work that talks to the server, run by the loop after it has drawn a spinner.
pub type Job = Box<dyn FnOnce(&mut App) -> Result<()>>;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tone {
    Info,
    Success,
    Error,
}

struct Toast {
    text: String,
    tone: Tone,
    at: Instant,
}

/// The last change you made, and how to take it back.
struct Undo {
    label: String,
    job: Job,
    at: Instant,
}

/// Refreshes live screens on another thread, so keys never wait for the server.
struct Background {
    client: Client,
    inflight: Option<Inflight>,
}

struct Inflight {
    receiver: Receiver<Result<Value>>,
    started: Instant,
    tool: Option<i64>,
}

const UNDO_FOR: Duration = Duration::from_secs(60);

struct Pending {
    label: String,
    job: Job,
    quiet: bool,
}

/// What a key press asks the app to do.
#[derive(Default)]
pub struct Fx {
    jobs: Vec<Pending>,
    pub popup: Option<Popup>,
    pub close_popup: bool,
    pub toast: Option<(String, Tone)>,
    pub open_url: Option<String>,
    pub open_tool: Option<i64>,
    /// A link into a tool: opens the tool, then what the link points at.
    pub open_link: Option<String>,
    pub back: bool,
    pub confetti: bool,
}

impl Fx {
    /// Queues `job`, with `label` next to the spinner while it runs.
    pub fn job(&mut self, label: impl Into<String>, job: impl FnOnce(&mut App) -> Result<()> + 'static) {
        self.jobs.push(Pending { label: label.into(), job: Box::new(job), quiet: false });
    }

    pub fn toast(&mut self, text: impl Into<String>, tone: Tone) {
        self.toast = Some((text.into(), tone));
    }
}

pub struct App {
    pub api: Box<dyn Api>,
    /// The server, e.g. https://app.dobase.co
    pub base: String,
    pub me: Value,
    pub tools: Vec<Value>,
    pub screen: Screen,
    pub popup: Option<Popup>,
    pub quit: bool,
    pub tick: u64,
    /// Whether `o` starts a browser; tests only record the URL.
    pub launch_browser: bool,
    pub opened: Vec<String>,
    toast: Option<Toast>,
    confetti: Option<Confetti>,
    jobs: VecDeque<Pending>,
    busy: Option<String>,
    last_refresh: Instant,
    /// When a job last changed something, so an older background refresh can't undo it on screen.
    last_change: Instant,
    undo: Option<Undo>,
    background: Option<Background>,
}

impl App {
    pub fn new(api: Box<dyn Api>, base: String) -> Self {
        Self {
            api,
            base: base.trim_end_matches('/').to_string(),
            me: Value::Null,
            tools: Vec::new(),
            screen: Screen::Home(screens::home::Home::default()),
            popup: None,
            quit: false,
            tick: 0,
            launch_browser: true,
            opened: Vec::new(),
            toast: None,
            confetti: None,
            jobs: VecDeque::new(),
            busy: None,
            last_refresh: Instant::now(),
            last_change: Instant::now(),
            undo: None,
            background: None,
        }
    }

    /// Refreshes live screens in the background with this client.
    pub fn refresh_in_background(&mut self, client: Client) {
        self.background = Some(Background { client, inflight: None });
    }

    /// Lets `u` take back what was just done, for a minute.
    pub fn offer_undo(&mut self, label: impl Into<String>, job: impl FnOnce(&mut App) -> Result<()> + 'static) {
        self.undo = Some(Undo { label: label.into(), job: Box::new(job), at: Instant::now() });
    }

    // -- API -----------------------------------------------------------------

    pub fn get(&mut self, path: &str, params: &[(&str, String)]) -> Result<Value> {
        self.api.request(Method::Get, path, params, &Value::Null)
    }

    pub fn post(&mut self, path: &str, body: Value) -> Result<Value> {
        self.api.request(Method::Post, path, &[], &body)
    }

    pub fn patch(&mut self, path: &str, body: Value) -> Result<Value> {
        self.api.request(Method::Patch, path, &[], &body)
    }

    pub fn delete(&mut self, path: &str) -> Result<Value> {
        self.api.request(Method::Delete, path, &[], &Value::Null)
    }

    /// Loads who's signed in, their tools and the home screen.
    pub fn start(&mut self) -> Result<()> {
        self.me = self.get("/profile", &[])?;
        self.load_tools()?;
        self.screen = Screen::Home(screens::home::Home::load(self)?);
        Ok(())
    }

    pub fn load_tools(&mut self) -> Result<()> {
        let mut tools = self.get("/tools", &[])?.items().to_vec();
        tools.sort_by_key(|tool| (tool["name"].s().to_lowercase(), tool["id"].int()));
        self.tools = tools;
        Ok(())
    }

    pub fn tool_url(&self, tool: &Value) -> String {
        tool["url"].opt().unwrap_or_else(|| format!("{}/tools/{}", self.base, tool["id"].s()))
    }

    // -- Keys ----------------------------------------------------------------

    pub fn key(&mut self, key: KeyEvent) {
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            self.quit = true;
            return;
        }
        let mut fx = Fx::default();

        if let Some(popup) = self.popup.as_mut() {
            popups::key(popup, key, &mut fx);
            self.apply(fx);
            return;
        }

        let view = View { tools: &self.tools, tick: self.tick, me: &self.me };
        if !self.screen.key(key, &view, &mut fx) {
            self.global_key(key, &mut fx);
        }
        self.apply(fx);
    }

    fn global_key(&mut self, key: KeyEvent, fx: &mut Fx) {
        let home = matches!(self.screen, Screen::Home(_));
        match key.code {
            KeyCode::Char('q') if home => self.quit = true,
            KeyCode::Char('q') | KeyCode::Esc | KeyCode::Char('g') => fx.back = true,
            KeyCode::Char('?') => fx.popup = Some(Popup::help(self.screen.help())),
            KeyCode::Char('/') => fx.popup = Some(Popup::search()),
            KeyCode::Char('n') => fx.job("Fetching notifications", |app| {
                let items = app.get("/notifications", &[("limit", "30".to_string())])?;
                app.popup = Some(Popup::notifications(items.items().to_vec()));
                Ok(())
            }),
            KeyCode::Char('r') => {
                if let Some(job) = self.screen.refresh() {
                    fx.jobs.push(Pending { label: "Refreshing".into(), job, quiet: false });
                } else {
                    fx.job("Refreshing", |app| {
                        app.load_tools()?;
                        let selected = if let Screen::Home(home) = &app.screen { home.selected } else { 0 };
                        let mut home = screens::home::Home::load(app)?;
                        home.selected = selected.min(app.tools.len().saturating_sub(1));
                        app.screen = Screen::Home(home);
                        Ok(())
                    });
                }
            }
            KeyCode::Char(']') | KeyCode::Char('[') => {
                if !self.tools.is_empty() {
                    let current = self.screen.tool().and_then(|tool| self.tools.iter().position(|other| other["id"] == tool["id"]));
                    let count = self.tools.len();
                    let next = match (current, key.code == KeyCode::Char(']')) {
                        (None, true) => 0,
                        (None, false) => count - 1,
                        (Some(index), true) => (index + 1) % count,
                        (Some(index), false) => (index + count - 1) % count,
                    };
                    fx.open_tool = Some(self.tools[next]["id"].int());
                }
            }
            KeyCode::Char('u') => match self.undo.take().filter(|undo| undo.at.elapsed() < UNDO_FOR) {
                Some(undo) => {
                    let job = undo.job;
                    fx.job(format!("Undoing {}", undo.label), move |app| {
                        job(app)?;
                        app.toast("Undone ↩", Tone::Info);
                        Ok(())
                    });
                }
                None => fx.toast("Nothing to undo", Tone::Info),
            },
            KeyCode::Char('o') => {
                fx.open_url = Some(match self.screen.tool() {
                    Some(tool) => self.tool_url(tool),
                    None => self.base.clone(),
                })
            }
            _ => {}
        }
    }

    fn apply(&mut self, fx: Fx) {
        if fx.close_popup {
            self.popup = None;
        }
        if let Some(popup) = fx.popup {
            self.popup = Some(popup);
        }
        if let Some((text, tone)) = fx.toast {
            self.toast(text, tone);
        }
        if let Some(url) = fx.open_url {
            self.open_url(url);
        }
        if fx.confetti {
            self.celebrate();
        }
        if fx.back {
            self.go_home();
        }
        if let Some(id) = fx.open_tool {
            self.open_tool(id);
        }
        if let Some(url) = fx.open_link {
            self.open_link(url);
        }
        self.jobs.extend(fx.jobs);
    }

    pub fn toast(&mut self, text: impl Into<String>, tone: Tone) {
        self.toast = Some(Toast { text: text.into(), tone, at: Instant::now() });
    }

    pub fn celebrate(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        self.confetti = Some(Confetti::new(0x9e37_79b9_7f4a_7c15 ^ (self.tick.wrapping_mul(2_654_435_761))));
        let cheer = theme::CHEERS[(self.tick as usize * 7) % theme::CHEERS.len()];
        self.toast(cheer, Tone::Success);
    }

    fn go_home(&mut self) {
        if matches!(self.screen, Screen::Home(_)) {
            return;
        }
        let selected = self.screen.tool().and_then(|tool| self.tools.iter().position(|other| other["id"] == tool["id"])).unwrap_or(0);
        self.jobs.push_back(Pending {
            label: "Going home".into(),
            quiet: false,
            job: Box::new(move |app: &mut App| {
                let mut home = screens::home::Home::load(app)?;
                home.selected = selected;
                app.screen = Screen::Home(home);
                Ok(())
            }),
        });
    }

    pub fn open_tool(&mut self, id: i64) {
        let Some(tool) = self.tools.iter().find(|tool| tool["id"].int() == id).cloned() else {
            self.toast("That tool isn't in your list any more.", Tone::Error);
            return;
        };
        let label = format!("Opening {}", tool["name"].s());
        self.jobs.push_back(Pending {
            label,
            quiet: false,
            job: Box::new(move |app: &mut App| {
                app.screen = screens::open(app, &tool)?;
                app.last_refresh = Instant::now();
                Ok(())
            }),
        });
    }

    /// Opens the tool a Dobase link is in, then the card, todo or document it points at.
    pub fn open_link(&mut self, url: String) {
        match screens::home::tool_id_in(&url) {
            Some(id) => {
                self.open_tool(id);
                self.jobs.push_back(Pending {
                    label: "Opening it".into(),
                    quiet: false,
                    job: Box::new(move |app: &mut App| screens::focus(app, &url)),
                });
            }
            None => self.open_url(url),
        }
    }

    /// Opens `url` in the browser; a path is on this server.
    pub fn open_url(&mut self, url: String) {
        let url = if url.starts_with('/') { format!("{}{url}", self.base) } else { url };
        self.opened.push(url.clone());
        if !self.launch_browser {
            return;
        }
        #[cfg(target_os = "macos")]
        let command = std::process::Command::new("open").arg(&url).spawn();
        #[cfg(target_os = "windows")]
        let command = std::process::Command::new("cmd").args(["/C", "start", "", &url]).spawn();
        #[cfg(not(any(target_os = "macos", target_os = "windows")))]
        let command = std::process::Command::new("xdg-open")
            .arg(&url)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
        match command {
            Ok(_) => self.toast("Opened in your browser", Tone::Info),
            Err(_) => self.toast(format!("Couldn't start a browser. The link: {url}"), Tone::Error),
        }
    }

    // -- The loop ------------------------------------------------------------

    /// Whether a job is waiting; its label goes by the spinner for the next draw.
    pub fn has_job(&mut self) -> bool {
        self.busy = self.jobs.front().filter(|pending| !pending.quiet).map(|pending| pending.label.clone());
        !self.jobs.is_empty()
    }

    /// Runs the first queued job; its error, if any, becomes a toast.
    pub fn run_job(&mut self) {
        let Some(pending) = self.jobs.pop_front() else { return };
        let result = (pending.job)(self);
        self.busy = None;
        self.last_change = Instant::now();
        if let Err(error) = result {
            let message = match error {
                Error::Usage(message) | Error::Failed(message) | Error::Help(message) => message,
            };
            self.toast(message, Tone::Error);
        }
    }

    /// Runs every queued job, for tests.
    #[cfg(test)]
    pub fn settle(&mut self) {
        while !self.jobs.is_empty() {
            self.run_job();
        }
    }

    /// Called a few times a second: animations, and a quiet refresh of live screens.
    pub fn on_tick(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        if self.confetti.as_ref().is_some_and(Confetti::finished) {
            self.confetti = None;
        }
        if self.toast.as_ref().is_some_and(|toast| toast.at.elapsed() > Duration::from_secs(4)) {
            self.toast = None;
        }
        self.poll_background();
    }

    /// Picks up a finished background refresh, and starts the next one every ten seconds.
    fn poll_background(&mut self) {
        let Some(background) = self.background.as_mut() else { return };
        let tool = self.screen.tool().map(|tool| tool["id"].int());

        if let Some(inflight) = &background.inflight {
            match inflight.receiver.try_recv() {
                Err(TryRecvError::Empty) => return,
                Ok(Ok(value)) if inflight.tool == tool && inflight.started > self.last_change => self.screen.apply_live(value),
                _ => {}
            }
            background.inflight = None;
        }

        if self.last_refresh.elapsed() < Duration::from_secs(10) || !self.jobs.is_empty() {
            return;
        }
        self.last_refresh = Instant::now();
        let Some((path, params)) = self.screen.live_request() else { return };
        let (sender, receiver) = mpsc::channel();
        let mut client = background.client.clone();
        std::thread::spawn(move || {
            let params: Vec<(&str, String)> = params.iter().map(|(name, value)| (*name, value.clone())).collect();
            let _ = sender.send(client.request(Method::Get, &path, &params, &Value::Null));
        });
        background.inflight = Some(Inflight { receiver, started: Instant::now(), tool });
    }

    // -- Drawing -------------------------------------------------------------

    pub fn draw(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if area.width < 50 || area.height < 14 {
            let message = Paragraph::new("Make the window a little bigger 🙂").style(theme::dim());
            frame.render_widget(message, area);
            return;
        }

        let [header, body, footer] = Layout::vertical([Constraint::Length(1), Constraint::Min(1), Constraint::Length(1)]).areas(area);
        self.draw_header(frame, header);
        let view = View { tools: &self.tools, tick: self.tick, me: &self.me };
        self.screen.draw(frame, body, &view);
        self.draw_footer(frame, footer);

        if let Some(popup) = self.popup.as_mut() {
            popups::draw(popup, frame);
        }
        if let Some(confetti) = &self.confetti {
            confetti.render(frame, body);
        }
    }

    fn draw_header(&self, frame: &mut Frame, area: Rect) {
        let mut left = vec![Span::styled(" dobase ", Style::new().fg(theme::accent()).add_modifier(Modifier::BOLD))];
        if let Some(tool) = self.screen.tool() {
            left.push(Span::styled("› ", theme::dim()));
            left.push(Span::raw(format!("{} ", theme::tool_icon(&tool["type"].s()))));
            left.push(Span::styled(tool["name"].s(), theme::bold()));
        }
        let host = self.base.split("://").nth(1).unwrap_or(&self.base).to_string();
        let right = Line::from(vec![Span::raw(self.me["name"].s()), Span::styled(format!(" · {host} "), theme::dim())]).right_aligned();
        frame.render_widget(Line::from(left), area);
        frame.render_widget(right, area);
    }

    fn draw_footer(&self, frame: &mut Frame, area: Rect) {
        let mut hints = match &self.popup {
            Some(popup) => popups::hints(popup),
            None => self.screen.hints(),
        };
        if self.popup.is_none() && self.undo.as_ref().is_some_and(|undo| undo.at.elapsed() < UNDO_FOR) {
            hints.insert(0, ("u", "undo"));
        }
        let mut pairs: Vec<(&str, &str)> = hints.iter().map(|(key, action)| (*key, *action)).collect();
        pairs.push(("?", "help"));
        let mut line = widgets::hints(&pairs);
        line.spans.insert(0, Span::raw(" "));
        frame.render_widget(line, area);

        let status = if let Some(label) = &self.busy {
            let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"][(self.tick % 10) as usize];
            Some(Line::from(vec![Span::styled(format!("{spinner} "), Style::new().fg(theme::accent())), Span::raw(format!("{label}… "))]))
        } else {
            self.toast.as_ref().map(|toast| {
                let color = match toast.tone {
                    Tone::Info => theme::accent(),
                    Tone::Success => theme::success(),
                    Tone::Error => theme::danger(),
                };
                let text = widgets::truncate(&toast.text, usize::from(area.width) * 2 / 3);
                Line::from(Span::styled(format!(" {text} "), Style::new().fg(color).add_modifier(Modifier::BOLD)))
            })
        };
        if let Some(status) = status {
            // The last cell stays empty: writing there makes some terminals scroll the whole screen.
            let width = (status.width() as u16).min(area.width.saturating_sub(1));
            let status_area = Rect { x: area.right().saturating_sub(width + 1), width, ..area };
            frame.render_widget(ratatui::widgets::Clear, status_area);
            frame.render_widget(status, status_area);
        }
    }
}
