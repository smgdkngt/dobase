//! Finds the command in the arguments, runs it, and prints help.

use std::io::{IsTerminal, Write};

use crate::command::{Ctx, Definition, Error, clean, ljust};
use crate::commands;
use crate::config::Config;

pub const VERSION: &str = match option_env!("DOBASE_VERSION") {
    Some(version) => version,
    None => "dev",
};

const INTRO: &str = "dobase: work in your Dobase tools from the command line.

Usage: dobase NOUN VERB [ARGS] [OPTIONS] [--json]

TOOL is a tool id or (part of) its name. Things inside a tool are TOOL/ID,
e.g. 12/104; list commands print these references. A TEXT value of \"-\" is
read from stdin. --json prints the raw API response instead of text.
`dobase help NOUN` shows the options of every command for that noun.";

/// Runs the CLI and returns its exit status.
pub fn run(argv: Vec<String>, out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let definitions = commands::definitions();
    let json = argv.iter().any(|arg| arg == "--json");
    let argv: Vec<String> = argv.into_iter().filter(|arg| arg != "--json").collect();

    match argv.first().map(String::as_str) {
        // A person at a terminal gets the app; scripts and pipes get the help.
        None if !json && std::io::stdin().is_terminal() && std::io::stdout().is_terminal() => {
            return match crate::tui::run(&mut Config::default(), &format!("dobase-cli/{VERSION}")) {
                Ok(()) => 0,
                Err(error) => {
                    let _ = writeln!(err, "Error: {}", clean(&error_message(error)));
                    1
                }
            };
        }
        None | Some("help" | "--help" | "-h") => {
            help(&definitions, argv.get(1).map(String::as_str), out);
            return 0;
        }
        Some("--version" | "version") => {
            let _ = writeln!(out, "dobase {VERSION}");
            return 0;
        }
        _ => {}
    }

    let Some((definition, rest)) = find(&definitions, &argv) else {
        let _ = writeln!(err, "Unknown command: dobase {}\n", argv.join(" "));
        help(&definitions, argv.first().map(String::as_str), out);
        return 2;
    };

    let result = definition.parse(rest).and_then(|args| {
        let mut ctx = Ctx::new(Config::default(), out, json, format!("dobase-cli/{VERSION}"));
        (definition.run)(&mut ctx, &args)
    });

    match result {
        Ok(()) => 0,
        Err(Error::Help(text)) => {
            let _ = write!(out, "{text}");
            0
        }
        Err(Error::Usage(message)) => {
            let _ = writeln!(err, "{}", clean(message.trim_end()));
            2
        }
        Err(Error::Failed(message)) => {
            let _ = writeln!(err, "Error: {}", clean(&message));
            1
        }
    }
}

fn error_message(error: Error) -> String {
    match error {
        Error::Usage(message) | Error::Failed(message) | Error::Help(message) => message,
    }
}

fn find<'a>(definitions: &'a [Definition], argv: &'a [String]) -> Option<(&'a Definition, &'a [String])> {
    if argv.len() >= 2 {
        let name = format!("{} {}", argv[0], argv[1]);
        if let Some(definition) = definitions.iter().find(|definition| definition.name == name) {
            return Some((definition, &argv[2..]));
        }
    }
    definitions.iter().find(|definition| definition.name == argv[0]).map(|definition| (definition, &argv[1..]))
}

/// Commands grouped by noun: general ones first, then tools, then the rest by name.
fn groups(definitions: &[Definition]) -> Vec<(Option<&'static str>, Vec<&Definition>)> {
    let mut groups: Vec<(Option<&'static str>, Vec<&Definition>)> = Vec::new();
    for definition in definitions {
        match groups.iter_mut().find(|(noun, _)| *noun == definition.noun()) {
            Some((_, members)) => members.push(definition),
            None => groups.push((definition.noun(), vec![definition])),
        }
    }
    groups.sort_by_key(|(noun, _)| match noun {
        None => (0, ""),
        Some("tool") => (1, "tool"),
        Some(noun) => (2, *noun),
    });
    groups
}

fn help(definitions: &[Definition], noun: Option<&str>, out: &mut dyn Write) {
    let nouns = commands::nouns();
    let summary = |noun: &str| nouns.iter().find(|(name, _)| *name == noun).map(|(_, summary)| *summary).unwrap_or("");
    let groups = groups(definitions);

    if let Some((Some(noun), members)) = noun.and_then(|noun| groups.iter().find(|(group, _)| *group == Some(noun))) {
        let _ = writeln!(out, "{noun}: {}\n", summary(noun));
        for definition in members {
            let _ = writeln!(out, "  {}", definition.usage());
            let _ = writeln!(out, "      {}", definition.summary);
            for flag in &definition.flags {
                let _ = writeln!(out, "      {} {}", ljust(&Definition::flag_label(flag), 26), flag.description);
            }
            let _ = writeln!(out);
        }
        return;
    }

    let _ = writeln!(out, "{INTRO}");
    for (noun, members) in &groups {
        let _ = writeln!(out);
        match noun {
            Some(noun) => {
                let _ = writeln!(out, "{noun}: {}", summary(noun));
            }
            None => {
                let _ = writeln!(out, "General");
            }
        }
        let width = members.iter().map(|definition| definition.usage().chars().count()).max().unwrap_or(0);
        for definition in members {
            let _ = writeln!(out, "  {}  {}", ljust(&definition.usage(), width), definition.summary);
        }
    }
}
