use crate::{roc_host, roc_platform_abi::*};
use reqwest::blocking::Client;
use std::{
    io::Read,
    mem::ManuallyDrop,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

type Error = BodyTooLargeOrConnectFailedOrInvalidHeaderOrInvalidRequestOrInvalidUrlOrInvalidUtf8OrRedirectLimitOrTimeoutOrUnsupportedScheme;

fn err(error: Error) -> HostGlueHttpSendResult {
    HostGlueHttpSendResult {
        payload: HostGlueHttpSendResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostGlueHttpSendResultTag::Err,
    }
}

pub fn send(args: HostGlueHttpSendArgs) -> HostGlueHttpSendResult {
    let url = args.url.as_str().to_owned();
    let body = args.body.as_str().as_bytes().to_vec();
    let headers: Vec<(String, String)> = args
        .headers
        .as_slice()
        .iter()
        .map(|header| {
            (
                header.name.as_str().to_owned(),
                header.value.as_str().to_owned(),
            )
        })
        .collect();
    let method = args.method;
    let timeout_ms = args.timeout_ms;
    let max_bytes = args.max_response_bytes;
    let max_redirects = args.max_redirects;
    unsafe { args.decref(roc_host()) };

    if !(1..=60_000).contains(&timeout_ms)
        || !(1..=4 * 1024 * 1024).contains(&max_bytes)
        || max_redirects > 10
        || body.len() > 1024 * 1024
        || headers.len() > 64
    {
        return err(Error::InvalidRequest);
    }
    let parsed = match reqwest::Url::parse(&url) {
        Ok(value) => value,
        Err(_) => return err(Error::InvalidUrl),
    };
    if !matches!(parsed.scheme(), "http" | "https") {
        return err(Error::UnsupportedScheme);
    }
    let header_bytes: usize = headers
        .iter()
        .map(|(name, value)| name.len() + value.len())
        .sum();
    if header_bytes > 32 * 1024 {
        return err(Error::InvalidHeader);
    }

    let redirected = Arc::new(AtomicBool::new(false));
    let marker = redirected.clone();
    let client = match Client::builder()
        .timeout(Duration::from_millis(timeout_ms))
        .redirect(reqwest::redirect::Policy::custom(move |attempt| {
            if attempt.previous().len() >= max_redirects as usize {
                marker.store(true, Ordering::Relaxed);
                attempt.stop()
            } else {
                attempt.follow()
            }
        }))
        .build()
    {
        Ok(value) => value,
        Err(_) => return err(Error::InvalidRequest),
    };
    let mut request = match method {
        GetOrPost::Get => client.get(parsed),
        GetOrPost::Post => client.post(parsed).body(body),
    };
    for (name, value) in headers {
        let name = match reqwest::header::HeaderName::from_bytes(name.as_bytes()) {
            Ok(v) => v,
            Err(_) => return err(Error::InvalidHeader),
        };
        let value = match reqwest::header::HeaderValue::from_str(&value) {
            Ok(v) => v,
            Err(_) => return err(Error::InvalidHeader),
        };
        request = request.header(name, value);
    }
    let response = match request.send() {
        Ok(value) => value,
        Err(error) if error.is_timeout() => return err(Error::Timeout),
        Err(error) if error.is_redirect() || redirected.load(Ordering::Relaxed) => {
            return err(Error::RedirectLimit);
        }
        Err(_) => return err(Error::ConnectFailed),
    };
    if redirected.load(Ordering::Relaxed) {
        return err(Error::RedirectLimit);
    }
    if response
        .content_length()
        .is_some_and(|length| length > max_bytes)
    {
        return err(Error::BodyTooLarge);
    }
    if response.headers().len() > 64
        || response
            .headers()
            .iter()
            .map(|(name, value)| name.as_str().len() + value.as_bytes().len())
            .sum::<usize>()
            > 32 * 1024
    {
        return err(Error::InvalidHeader);
    }
    let status = response.status().as_u16();
    let output_headers: Vec<AnonStruct82a96c5d55d63488> = response
        .headers()
        .iter()
        .map(|(name, value)| AnonStruct82a96c5d55d63488 {
            name: RocStr::from_str(name.as_str(), roc_host()),
            value: RocStr::from_str(value.to_str().unwrap_or("<non-text>"), roc_host()),
        })
        .collect();
    let mut bytes = Vec::new();
    if response
        .take(max_bytes + 1)
        .read_to_end(&mut bytes)
        .is_err()
    {
        return err(Error::ConnectFailed);
    }
    if bytes.len() as u64 > max_bytes {
        return err(Error::BodyTooLarge);
    }
    let body = match String::from_utf8(bytes) {
        Ok(value) => value,
        Err(_) => return err(Error::InvalidUtf8),
    };
    let result = AnonStruct4cc00b7fc76acdb9 {
        body: RocStr::from_str(&body, roc_host()),
        headers: unsafe { RocList::from_slice(&output_headers, roc_host()) },
        status,
    };
    HostGlueHttpSendResult {
        payload: HostGlueHttpSendResultPayload {
            ok: ManuallyDrop::new(result),
        },
        tag: HostGlueHttpSendResultTag::Ok,
    }
}
