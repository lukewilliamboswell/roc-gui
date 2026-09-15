use crate::{roc_host, roc_platform_abi::*};
use reqwest::{Method, Url, blocking::Client};
use std::{
    collections::HashMap,
    io::Read,
    mem::ManuallyDrop,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
type Error = AccessDeniedOrBodyTooLargeOrConnectFailedOrInvalidCapabilityOrInvalidHeaderOrInvalidRequestOrInvalidUrlOrRedirectLimitOrTimeoutOrUnsupportedScheme;
struct Store {
    next: u64,
    granted: Option<Url>,
    clients: HashMap<u64, Arc<Url>>,
    allocations: HashMap<usize, u64>,
}
static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            granted: None,
            clients: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}
fn same_origin(a: &Url, b: &Url) -> bool {
    a.scheme() == b.scheme()
        && a.host_str() == b.host_str()
        && a.port_or_known_default() == b.port_or_known_default()
}
pub fn configure(origin: Option<&str>) -> Result<(), String> {
    let granted = match origin {
        None => None,
        Some(raw) => {
            let url =
                Url::parse(raw).map_err(|_| "HTTP origin must be an absolute URL".to_string())?;
            if !matches!(url.scheme(), "http" | "https")
                || url.host_str().is_none()
                || url.path() != "/"
                || url.query().is_some()
                || url.fragment().is_some()
            {
                return Err(
                    "HTTP grant must be an http(s) origin without path, query, or fragment".into(),
                );
            }
            Some(url)
        }
    };
    store().lock().unwrap().granted = granted;
    Ok(())
}
fn err(error: Error) -> HostGlueHttpSendResult {
    HostGlueHttpSendResult {
        payload: HostGlueHttpSendResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostGlueHttpSendResultTag::Err,
    }
}
pub fn acquire() -> HostGlueHttpAcquireResult {
    let mut g = store().lock().unwrap();
    let Some(origin) = g.granted.clone() else {
        return HostGlueHttpAcquireResult {
            payload: HostGlueHttpAcquireResultPayload {
                err: ManuallyDrop::new(Error::AccessDenied),
            },
            tag: HostGlueHttpAcquireResultTag::Err,
        };
    };
    let id = g.next;
    g.next += 1;
    let handle = unsafe { allocate_box(8, 8, false, roc_host()) as *mut u64 };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) } as usize;
    g.clients.insert(id, Arc::new(origin));
    g.allocations.insert(base, id);
    HostGlueHttpAcquireResult {
        payload: HostGlueHttpAcquireResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: HostGlueHttpAcquireResultTag::Ok,
    }
}
fn lookup(handle: *mut u64) -> Option<Arc<Url>> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.clients.get(&id).cloned()
}
pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut g = store().lock().unwrap();
    if let Some(id) = g.allocations.remove(&(base as usize)) {
        g.clients.remove(&id);
    }
}
pub fn send(args: HostGlueHttpSendArgs) -> HostGlueHttpSendResult {
    let origin = lookup(args.client);
    let url = args.url.as_str().to_owned();
    let body = args.body.as_slice().to_vec();
    let headers: Vec<(String, String)> = args
        .headers
        .as_slice()
        .iter()
        .map(|h| (h._0.as_str().to_owned(), h._1.as_str().to_owned()))
        .collect();
    let method_code = args.method;
    let method_ext = args.method_ext.as_str().to_owned();
    let timeout = args.timeout_ms;
    let limit = args.max_response_bytes;
    let redirects = args.max_redirects;
    unsafe { args.decref(roc_host()) };
    let Some(origin) = origin else {
        return err(Error::InvalidCapability);
    };
    if !(1..=60000).contains(&timeout)
        || !(1..=4 * 1024 * 1024).contains(&limit)
        || redirects > 10
        || body.len() > 1024 * 1024
        || headers.len() > 64
    {
        return err(Error::InvalidRequest);
    }
    let parsed = match Url::parse(&url) {
        Ok(v) => v,
        Err(_) => return err(Error::InvalidUrl),
    };
    if !matches!(parsed.scheme(), "http" | "https") {
        return err(Error::UnsupportedScheme);
    }
    if !same_origin(&origin, &parsed) {
        return err(Error::AccessDenied);
    }
    if headers
        .iter()
        .map(|(n, v)| n.len() + v.len())
        .sum::<usize>()
        > 32768
    {
        return err(Error::InvalidHeader);
    }
    let method = match method_code {
        0 => Method::CONNECT,
        1 => Method::DELETE,
        2 => Method::from_bytes(b"QUERY").unwrap(),
        3 => Method::GET,
        4 => Method::HEAD,
        5 => Method::OPTIONS,
        6 => Method::PATCH,
        7 => Method::POST,
        8 => Method::PUT,
        9 => Method::TRACE,
        10 => match Method::from_bytes(method_ext.as_bytes()) {
            Ok(v) => v,
            Err(_) => return err(Error::InvalidRequest),
        },
        _ => return err(Error::InvalidRequest),
    };
    let stopped = Arc::new(AtomicBool::new(false));
    let marker = stopped.clone();
    let allowed = origin.clone();
    let client = match Client::builder()
        .timeout(Duration::from_millis(timeout))
        .redirect(reqwest::redirect::Policy::custom(move |a| {
            if !same_origin(&allowed, a.url()) || a.previous().len() >= redirects as usize {
                marker.store(true, Ordering::Relaxed);
                a.stop()
            } else {
                a.follow()
            }
        }))
        .build()
    {
        Ok(v) => v,
        Err(_) => return err(Error::InvalidRequest),
    };
    let mut request = client.request(method, parsed).body(body);
    for (n, v) in headers {
        let n = match reqwest::header::HeaderName::from_bytes(n.as_bytes()) {
            Ok(x) => x,
            Err(_) => return err(Error::InvalidHeader),
        };
        let v = match reqwest::header::HeaderValue::from_str(&v) {
            Ok(x) => x,
            Err(_) => return err(Error::InvalidHeader),
        };
        request = request.header(n, v)
    }
    let response = match request.send() {
        Ok(v) => v,
        Err(e) if e.is_timeout() => return err(Error::Timeout),
        Err(_) => return err(Error::ConnectFailed),
    };
    if stopped.load(Ordering::Relaxed) {
        return err(Error::RedirectLimit);
    }
    if response.content_length().is_some_and(|n| n > limit) {
        return err(Error::BodyTooLarge);
    }
    if response.headers().len() > 64
        || response
            .headers()
            .iter()
            .map(|(n, v)| n.as_str().len() + v.as_bytes().len())
            .sum::<usize>()
            > 32768
    {
        return err(Error::InvalidHeader);
    }
    let status = response.status().as_u16();
    let hs: Vec<AnonStruct77eaba63dfee299d> = response
        .headers()
        .iter()
        .map(|(n, v)| AnonStruct77eaba63dfee299d {
            _0: RocStr::from_str(n.as_str(), roc_host()),
            _1: RocStr::from_str(v.to_str().unwrap_or("<non-text>"), roc_host()),
        })
        .collect();
    let mut bytes = Vec::new();
    if response.take(limit + 1).read_to_end(&mut bytes).is_err() {
        return err(Error::ConnectFailed);
    }
    if bytes.len() as u64 > limit {
        return err(Error::BodyTooLarge);
    }
    HostGlueHttpSendResult {
        payload: HostGlueHttpSendResultPayload {
            ok: ManuallyDrop::new(AnonStructBe6bcbc15f8a1360 {
                body: unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host()) },
                headers: unsafe { RocList::from_slice(&hs, roc_host()) },
                status,
            }),
        },
        tag: HostGlueHttpSendResultTag::Ok,
    }
}
