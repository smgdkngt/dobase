//! Thin JSON-over-HTTP wrapper around the Dobase API.

use std::fs::File;
use std::io::{self, Read};
use std::path::Path;
use std::time::Duration;

use serde_json::Value;
use ureq::Agent;
use ureq::http::{HeaderMap, Response, StatusCode};
use url::Url;

use crate::command::{Error, Result};
use crate::value::Json;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Method {
    Get,
    Post,
    Patch,
    Delete,
}

/// What commands need from the server. Tests swap in a fake.
pub trait Api {
    /// Sends a request; `Value::Null` means the server sent no content.
    fn request(&mut self, method: Method, path: &str, params: &[(&str, String)], body: &Value) -> Result<Value>;
    /// Multipart POST: `files` pairs a form field with a local path.
    fn upload(&mut self, path: &str, files: &[(&str, &str)], fields: &[(&str, String)]) -> Result<Value>;
    /// Streams a download to `destination`, following redirects. Returns the filename the server suggested.
    fn download(&mut self, path: &str, destination: &Path) -> Result<Option<String>>;
}

#[derive(Clone)]
pub struct Client {
    base: Url,
    token: String,
    user_agent: String,
    agent: Agent,
}

type HttpResponse = Response<ureq::Body>;

impl Client {
    pub fn new(url: Option<String>, token: Option<String>, user_agent: &str) -> Result<Self> {
        let (Some(url), Some(token)) = (url, token) else {
            return Err(Error::failed("Not signed in. Run `dobase login URL` first, or set DOBASE_URL and DOBASE_TOKEN."));
        };
        let base = Url::parse(&format!("{}/", url.trim_end_matches('/'))).map_err(|_| Error::failed(format!("{url} is not a URL.")))?;

        let agent = Agent::config_builder()
            .max_redirects(0)
            .http_status_as_error(false)
            .timeout_connect(Some(Duration::from_secs(10)))
            .timeout_recv_response(Some(Duration::from_secs(60)))
            .timeout_recv_body(Some(Duration::from_secs(60)))
            .build()
            .into();

        Ok(Self { base, token, user_agent: user_agent.to_string(), agent })
    }

    fn url_for(&self, path: &str) -> Result<Url> {
        let joined = if path.starts_with("http://") || path.starts_with("https://") {
            Url::parse(path)
        } else {
            self.base.join(path.trim_start_matches('/'))
        };
        joined.map_err(|_| Error::failed(format!("Can't make a URL of {path}")))
    }

    /// The token only goes to the configured server, never to a redirect target elsewhere.
    fn headers(&self, url: &Url) -> Vec<(&'static str, String)> {
        let mut headers = vec![("Accept", "application/json".to_string()), ("User-Agent", self.user_agent.clone())];
        if url.host_str() == self.base.host_str() && url.port_or_known_default() == self.base.port_or_known_default() {
            headers.push(("Authorization", format!("Bearer {}", self.token)));
        }
        headers
    }

    fn unreachable(&self, error: ureq::Error) -> Error {
        let base = self.base.as_str().trim_end_matches('/');
        Error::failed(format!("Could not reach {base}: {error}"))
    }

    fn send(&self, method: Method, url: &Url, body: Option<(&str, Vec<u8>)>) -> Result<HttpResponse> {
        let headers = self.headers(url);
        let result = match method {
            Method::Get => with_headers(self.agent.get(url.as_str()), &headers).call(),
            Method::Delete => {
                let request = with_headers(self.agent.delete(url.as_str()), &headers);
                match body {
                    Some((content_type, bytes)) => request.header("Content-Type", content_type).force_send_body().send(&bytes[..]),
                    None => request.call(),
                }
            }
            Method::Post | Method::Patch => {
                let request = if method == Method::Post { self.agent.post(url.as_str()) } else { self.agent.patch(url.as_str()) };
                let request = with_headers(request, &headers);
                match body {
                    Some((content_type, bytes)) => request.header("Content-Type", content_type).send(&bytes[..]),
                    None => request.send_empty(),
                }
            }
        };
        result.map_err(|error| self.unreachable(error))
    }

    fn json(&self, mut response: HttpResponse) -> Result<Value> {
        let status = response.status();
        if status == StatusCode::NO_CONTENT {
            return Ok(Value::Null);
        }
        if status.is_redirection() {
            return Err(Error::failed(format!(
                "The server redirected to {} instead of answering. This action may not be available through the API.",
                header(response.headers(), "location")
            )));
        }

        let body = read_body(&mut response).map_err(|error| Error::failed(format!("Could not read the response: {error}")))?;
        if !status.is_success() {
            return Err(api_error(status, &body));
        }
        if body.trim().is_empty() {
            return Ok(Value::Null);
        }
        serde_json::from_str(&body)
            .map_err(|_| Error::failed(format!("The server sent something other than JSON (HTTP {}).", status.as_u16())))
    }
}

impl Api for Client {
    fn request(&mut self, method: Method, path: &str, params: &[(&str, String)], body: &Value) -> Result<Value> {
        let mut url = self.url_for(path)?;
        if !params.is_empty() {
            let mut query = url.query_pairs_mut();
            for (name, value) in params {
                query.append_pair(name, value);
            }
        }

        let empty = body.is_null() || body.as_object().is_some_and(|object| object.is_empty());
        let body = (!empty).then(|| ("application/json", serde_json::to_vec(body).unwrap()));
        let response = self.send(method, &url, body)?;
        self.json(response)
    }

    fn upload(&mut self, path: &str, files: &[(&str, &str)], fields: &[(&str, String)]) -> Result<Value> {
        let url = self.url_for(path)?;
        let boundary = format!("dobase-{:x}{:x}", std::process::id(), jiff::Timestamp::now().as_nanosecond());

        // The form is streamed: text parts in memory, files read from disk as they're sent.
        let mut length: u64 = 0;
        let mut parts: Vec<Box<dyn Read>> = Vec::new();
        let text = |part: String, length: &mut u64, parts: &mut Vec<Box<dyn Read>>| {
            *length += part.len() as u64;
            parts.push(Box::new(io::Cursor::new(part.into_bytes())));
        };

        for (name, value) in fields {
            text(
                format!("--{boundary}\r\nContent-Disposition: form-data; name=\"{}\"\r\n\r\n{value}\r\n", escape_quotes(name)),
                &mut length,
                &mut parts,
            );
        }
        for (name, file_path) in files {
            let file = File::open(file_path).map_err(|error| Error::io(Path::new(file_path), error))?;
            let size = file.metadata().map_err(|error| Error::io(Path::new(file_path), error))?.len();
            let filename = Path::new(file_path).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
            text(
                format!(
                    "--{boundary}\r\nContent-Disposition: form-data; name=\"{}\"; filename=\"{}\"\r\nContent-Type: {}\r\n\r\n",
                    escape_quotes(name),
                    escape_quotes(&filename),
                    content_type_for(file_path)
                ),
                &mut length,
                &mut parts,
            );
            length += size;
            parts.push(Box::new(file));
            text("\r\n".to_string(), &mut length, &mut parts);
        }
        text(format!("--{boundary}--\r\n"), &mut length, &mut parts);

        let mut reader = parts.into_iter().fold(Box::new(io::empty()) as Box<dyn Read>, |all, part| Box::new(all.chain(part)));
        let request = with_headers(self.agent.post(url.as_str()), &self.headers(&url))
            .header("Content-Type", format!("multipart/form-data; boundary={boundary}"))
            .header("Content-Length", length.to_string());
        let response = request.send(ureq::SendBody::from_reader(&mut reader)).map_err(|error| self.unreachable(error))?;
        self.json(response)
    }

    fn download(&mut self, path: &str, destination: &Path) -> Result<Option<String>> {
        let mut url = self.url_for(path)?;

        for _ in 0..=5 {
            let mut response = self.send(Method::Get, &url, None)?;
            let status = response.status();

            if status.is_redirection() {
                let location = header(response.headers(), "location");
                url = url.join(&location).map_err(|_| Error::failed(format!("The server redirected to {location}, which isn't a URL.")))?;
                continue;
            }
            if !status.is_success() {
                let body = read_body(&mut response).unwrap_or_default();
                return Err(api_error(status, &body));
            }

            let filename = header(response.headers(), "content-disposition")
                .split("filename=\"")
                .nth(1)
                .and_then(|rest| rest.split('"').next())
                .map(str::to_string);
            let mut file = File::create(destination).map_err(|error| Error::io(destination, error))?;
            let mut body = response.body_mut().with_config().limit(u64::MAX).reader();
            io::copy(&mut body, &mut file).map_err(|error| Error::failed(format!("Download failed: {error}")))?;
            return Ok(filename);
        }

        Err(Error::failed("Too many redirects"))
    }
}

fn with_headers<B>(mut request: ureq::RequestBuilder<B>, headers: &[(&'static str, String)]) -> ureq::RequestBuilder<B> {
    for (name, value) in headers {
        request = request.header(*name, value);
    }
    request
}

fn header(headers: &HeaderMap, name: &str) -> String {
    headers.get(name).and_then(|value| value.to_str().ok()).unwrap_or_default().to_string()
}

fn read_body(response: &mut HttpResponse) -> std::result::Result<String, ureq::Error> {
    response.body_mut().with_config().limit(u64::MAX).read_to_string()
}

fn api_error(status: StatusCode, body: &str) -> Error {
    let message = match serde_json::from_str::<Value>(body) {
        Ok(data) => {
            let errors = if data["errors"].is_null() { &data["error"] } else { &data["errors"] };
            match errors {
                Value::Array(list) => list.iter().map(Json::s).collect::<Vec<_>>().join(", "),
                other => other.s(),
            }
        }
        Err(_) => {
            let line = body.trim().lines().next().unwrap_or("").trim();
            if line.is_empty() { "Request failed".to_string() } else { line.chars().take(200).collect() }
        }
    };
    Error::failed(format!("{message} (HTTP {})", status.as_u16()))
}

fn escape_quotes(text: &str) -> String {
    text.replace('"', "%22").replace(['\r', '\n'], " ")
}

fn content_type_for(path: &str) -> &'static str {
    let extension = Path::new(path).extension().map(|extension| extension.to_string_lossy().to_lowercase()).unwrap_or_default();
    match extension.as_str() {
        "csv" => "text/csv",
        "doc" => "application/msword",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "gif" => "image/gif",
        "htm" | "html" => "text/html",
        "ics" => "text/calendar",
        "jpeg" | "jpg" => "image/jpeg",
        "json" => "application/json",
        "md" => "text/markdown",
        "mov" => "video/quicktime",
        "mp3" => "audio/mpeg",
        "mp4" => "video/mp4",
        "ogg" => "audio/ogg",
        "pdf" => "application/pdf",
        "png" => "image/png",
        "ppt" => "application/vnd.ms-powerpoint",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "svg" => "image/svg+xml",
        "txt" => "text/plain",
        "wav" => "audio/wav",
        "webm" => "video/webm",
        "webp" => "image/webp",
        "xls" => "application/vnd.ms-excel",
        "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    }
}
