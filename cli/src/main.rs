//! Command-line client for the Dobase API. Run `dobase help` to get started.

mod cli;
mod client;
mod command;
mod commands;
mod config;
mod value;

#[cfg(test)]
mod tests;

fn main() {
    let argv = std::env::args_os().skip(1).map(|arg| arg.to_string_lossy().into_owned()).collect();
    let status = cli::run(argv, &mut std::io::stdout(), &mut std::io::stderr());
    std::process::exit(status);
}
