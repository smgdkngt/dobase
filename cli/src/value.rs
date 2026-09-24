//! Reading the loosely typed JSON the API sends. Missing fields read as empty,
//! so output code can stay short, like string interpolation in a template.

use serde_json::Value;

pub trait Json {
    /// The value as text: strings as they are, numbers written out, null as "".
    fn s(&self) -> String;
    /// `Some(text)` unless the value is null or missing.
    fn opt(&self) -> Option<String>;
    /// True unless null, missing or false.
    fn truthy(&self) -> bool;
    /// The items of an array, or none.
    fn items(&self) -> &[Value];
    fn int(&self) -> i64;
}

impl Json for Value {
    fn s(&self) -> String {
        match self {
            Value::Null => String::new(),
            Value::String(text) => text.clone(),
            other => other.to_string(),
        }
    }

    fn opt(&self) -> Option<String> {
        (!self.is_null()).then(|| self.s())
    }

    fn truthy(&self) -> bool {
        !matches!(self, Value::Null | Value::Bool(false))
    }

    fn items(&self) -> &[Value] {
        self.as_array().map(Vec::as_slice).unwrap_or(&[])
    }

    fn int(&self) -> i64 {
        match self {
            Value::Number(number) => number.as_i64().unwrap_or(0),
            Value::String(text) => text.parse().unwrap_or(0),
            _ => 0,
        }
    }
}

/// Drops the null fields of an object, for request bodies that leave out what wasn't given.
pub fn compact(mut value: Value) -> Value {
    if let Value::Object(map) = &mut value {
        map.retain(|_, field| !field.is_null());
    }
    value
}

/// Joins the parts that aren't empty.
pub fn join(parts: impl IntoIterator<Item = Option<String>>, separator: &str) -> String {
    parts.into_iter().flatten().filter(|part| !part.is_empty()).collect::<Vec<_>>().join(separator)
}

pub fn is_digits(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit())
}
