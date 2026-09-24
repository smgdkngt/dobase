use std::io::{BufRead, IsTerminal, Write};

use crate::client::Client;
use crate::command::{Args, Ctx, Definition, Error, Result, command, person, quoted, usage};
use crate::value::Json;

pub fn definitions() -> Vec<Definition> {
    vec![
        command("login", "Save the server URL and an access token for this machine", &["[URL]"], vec![], login),
        command("logout", "Forget the saved URL and token (revoke the token under Profile → API)", &[], vec![], logout),
        command("whoami", "Show who the token belongs to and what it may do", &[], vec![], whoami),
    ]
}

fn login(ctx: &mut Ctx, args: &Args) -> Result<()> {
    let url = match args.get(0).map(str::to_string).or_else(|| ctx.config.url()) {
        Some(url) => url,
        None => ask("Dobase URL: ", false)?,
    };
    let mut url = url.trim().trim_end_matches('/').to_string();
    if !url.starts_with("http://") && !url.starts_with("https://") {
        url = format!("https://{url}");
    }

    eprintln!("Create an access token under Profile → API: {url}/profile/edit?tab=api");
    let token = ask("Access token: ", true)?.trim().to_string();
    if token.is_empty() {
        usage!("No token given.");
    }

    let client = Client::new(Some(url.clone()), Some(token.clone()), &ctx.user_agent)?;
    ctx.set_api(Box::new(client));
    let profile = ctx.get("/profile", &[])?;
    ctx.config.save(&url, &token)?;

    ctx.say(format!("Signed in to {url} as {}.", person(&profile).unwrap_or_default()));
    let permission = if profile["access_token"]["permission"].s() == "write" { "read and write" } else { "only read" };
    ctx.say(format!("Token {} can {permission}.", quoted(&profile["access_token"]["name"].s())));
    Ok(())
}

fn logout(ctx: &mut Ctx, _args: &Args) -> Result<()> {
    ctx.config.forget()?;
    ctx.say("Signed out. The token still works until you revoke it under Profile → API.");
    Ok(())
}

fn whoami(ctx: &mut Ctx, _args: &Args) -> Result<()> {
    let profile = ctx.me()?;
    ctx.output(&profile, |ctx| {
        let url = ctx.config.url().unwrap_or_default();
        ctx.say(format!("{} on {url}", person(&profile).unwrap_or_default()));
        let token = &profile["access_token"];
        if !token.is_null() {
            let permission = if token["permission"].s() == "write" { "read and write" } else { "read only" };
            ctx.say(format!("Token {} ({permission})", quoted(&token["name"].s())));
        }
        Ok(())
    })
}

/// Prompts only when someone is typing; a piped token is read silently.
fn ask(prompt: &str, secret: bool) -> Result<String> {
    let stdin = std::io::stdin();
    let read_line = || {
        let mut line = String::new();
        stdin.lock().read_line(&mut line).map(|_| line)
    };

    let answer = if !stdin.is_terminal() {
        read_line()
    } else {
        eprint!("{prompt}");
        let _ = std::io::stderr().flush();
        if secret { rpassword::read_password() } else { read_line() }
    };
    answer.map_err(|error| Error::failed(format!("Could not read the answer: {error}")))
}
