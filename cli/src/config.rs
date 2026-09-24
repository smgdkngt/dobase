//! Where the CLI finds its server and token. DOBASE_URL and DOBASE_TOKEN
//! override the saved config, which lives in ~/.config/dobase/config.json.

use std::fs;
use std::path::PathBuf;

use serde_json::{Value, json};

use crate::command::{Error, Result};
use crate::value::Json;

#[derive(Default)]
pub struct Config {
    saved: Option<Value>,
}

impl Config {
    pub fn path() -> PathBuf {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| std::env::home_dir().unwrap_or_default().join(".config"));
        base.join("dobase").join("config.json")
    }

    pub fn url(&mut self) -> Option<String> {
        env("DOBASE_URL").or_else(|| self.saved()["url"].opt()).map(|url| url.trim_end_matches('/').to_string())
    }

    pub fn token(&mut self) -> Option<String> {
        env("DOBASE_TOKEN").or_else(|| self.saved()["token"].opt())
    }

    pub fn save(&mut self, url: &str, token: &str) -> Result<()> {
        let path = Self::path();
        let dir = path.parent().expect("config path has a directory");
        fs::create_dir_all(dir).map_err(|error| Error::io(dir, error))?;
        let contents = serde_json::to_string_pretty(&json!({ "url": url.trim_end_matches('/'), "token": token })).unwrap();

        #[cfg(unix)]
        {
            use std::fs::OpenOptions;
            use std::io::Write;
            use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

            fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|error| Error::io(dir, error))?;
            let mut file = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .mode(0o600)
                .open(&path)
                .map_err(|error| Error::io(&path, error))?;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).map_err(|error| Error::io(&path, error))?;
            file.write_all(contents.as_bytes()).map_err(|error| Error::io(&path, error))?;
        }
        #[cfg(not(unix))]
        fs::write(&path, contents).map_err(|error| Error::io(&path, error))?;

        self.saved = None;
        Ok(())
    }

    pub fn forget(&mut self) -> Result<()> {
        let path = Self::path();
        match fs::remove_file(&path) {
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => return Err(Error::io(&path, error)),
            _ => {}
        }
        self.saved = None;
        Ok(())
    }

    fn saved(&mut self) -> &Value {
        self.saved.get_or_insert_with(|| {
            fs::read_to_string(Self::path()).ok().and_then(|contents| serde_json::from_str(&contents).ok()).unwrap_or(Value::Null)
        })
    }
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}
