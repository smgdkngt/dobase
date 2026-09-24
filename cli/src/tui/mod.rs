//! `dobase` without arguments in a terminal: a full-screen app to look around
//! your tools, move cards, tick off todos and chat.

mod app;
mod popups;
mod screens;
mod theme;
mod widgets;

#[cfg(test)]
mod tests;

use std::time::Duration;

use ratatui::crossterm::event::{self, Event, KeyEventKind};

use crate::client::Client;
use crate::command::{Error, Result};
use crate::config::Config;
use app::App;

pub fn run(config: &mut Config, user_agent: &str) -> Result<()> {
    let url = config.url();
    let client = Client::new(url.clone(), config.token(), user_agent)?;
    let mut app = App::new(Box::new(client), url.unwrap_or_default());
    eprint!("Loading your workspace…");
    app.start()?;
    eprint!("\r\x1b[2K");

    let mut terminal = ratatui::try_init().map_err(|error| Error::failed(format!("Can't start the app in this terminal: {error}")))?;
    let result = run_loop(&mut terminal, &mut app);
    ratatui::restore();
    result.map_err(|error| Error::failed(format!("The terminal went away: {error}")))
}

fn run_loop(terminal: &mut ratatui::DefaultTerminal, app: &mut App) -> std::io::Result<()> {
    while !app.quit {
        let job = app.has_job();
        terminal.draw(|frame| app.draw(frame))?;

        // A queued job runs after the spinner is on screen.
        if job {
            app.run_job();
            continue;
        }

        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) if key.kind == KeyEventKind::Press => app.key(key),
                _ => {}
            }
        }
        app.on_tick();
    }
    Ok(())
}
