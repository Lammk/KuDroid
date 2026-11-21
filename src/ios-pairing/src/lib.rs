use base64::{engine::general_purpose::STANDARD, Engine};
use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::ffi::{c_char, CStr, CString};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::oneshot;

pub struct PairingSession {
    description: CString,
    events: Arc<Mutex<VecDeque<Value>>>,
    cancel: Option<oneshot::Sender<()>>,
}

fn publish(events: &Mutex<VecDeque<Value>>, value: Value) {
    if let Ok(mut queue) = events.lock() {
        if queue.len() >= 32 { queue.pop_front(); }
        queue.push_back(value);
    }
}

fn begin(name: String, identifier: String) -> Result<PairingSession, String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;
    let socket = socket2::Socket::new(socket2::Domain::IPV6, socket2::Type::STREAM, Some(socket2::Protocol::TCP))
        .map_err(|e| e.to_string())?;
    socket.set_only_v6(false).map_err(|e| e.to_string())?;
    socket.bind(&std::net::SocketAddr::from((std::net::Ipv6Addr::UNSPECIFIED, 0)).into())
        .map_err(|e| e.to_string())?;
    socket.listen(16).map_err(|e| e.to_string())?;
    socket.set_nonblocking(true).map_err(|e| e.to_string())?;
    let listener = {
        let _entered = runtime.enter();
        tokio::net::TcpListener::from_std(socket.into()).map_err(|e| e.to_string())?
    };
    let pairing = RpPairingFile::generate(&identifier);
    let info = PairableHostInfo::generate(name, "Mac");
    let txt: std::collections::BTreeMap<_, _> = info
        .mdns_txt_records(pairing.identifier())
        .into_iter()
        .collect();
    let description = CString::new(json!({
        "port": listener.local_addr().map_err(|e| e.to_string())?.port(),
        "identifier": pairing.identifier(),
        "txt": txt
    }).to_string()).map_err(|e| e.to_string())?;
    let events = Arc::new(Mutex::new(VecDeque::new()));
    let worker_events = Arc::clone(&events);
    let (cancel, cancelled) = oneshot::channel();
    std::thread::Builder::new()
        .name("remote-pairing".into())
        .spawn(move || {
            runtime.block_on(async move {
                let exchange = async {
                    loop {
                        let (socket, _) = listener.accept().await.map_err(|e| e.to_string())?;
                        let mut candidate = RpPairingFile::generate(&identifier);
                        let mut host = PairableHost::new(RpPairingSocket::new_device(socket), info.clone());
                        let pin_events = Arc::clone(&worker_events);
                        let attempt = host.accept(&mut candidate, move |pin| async move {
                            publish(&pin_events, json!({"type": "pin", "value": pin}));
                        });
                        match tokio::time::timeout(Duration::from_secs(120), attempt).await {
                            Ok(Ok(_)) => return Ok::<_, String>(candidate.to_bytes()),
                            _ => publish(&worker_events, json!({
                                "type": "retry",
                                "value": "The pairing connection ended. Select this host again in Settings."
                            })),
                        }
                    }
                };
                tokio::select! {
                    _ = cancelled => {},
                    result = tokio::time::timeout(Duration::from_secs(300), exchange) => {
                        let event = match result {
                            Ok(Ok(bytes)) => json!({"type": "paired", "record": STANDARD.encode(bytes)}),
                            Ok(Err(error)) => json!({"type": "error", "value": error}),
                            Err(_) => json!({"type": "error", "value": "Pairing timed out. Start pairing again."}),
                        };
                        publish(&worker_events, event);
                    }
                }
            });
        })
        .map_err(|e| e.to_string())?;
    Ok(PairingSession { description, events, cancel: Some(cancel) })
}

unsafe fn text(value: *const c_char) -> Option<String> {
    if value.is_null() { return None; }
    CStr::from_ptr(value).to_str().ok().filter(|v| !v.is_empty()).map(str::to_owned)
}

#[no_mangle]
pub unsafe extern "C" fn kudroid_pairing_start(
    name: *const c_char,
    identifier: *const c_char,
    error: *mut *mut c_char,
) -> *mut PairingSession {
    if !error.is_null() { *error = std::ptr::null_mut(); }
    let result = match (text(name), text(identifier)) {
        (Some(name), Some(identifier)) => begin(name, identifier),
        _ => Err("A display name and host identifier are required.".into()),
    };
    match result {
        Ok(session) => Box::into_raw(Box::new(session)),
        Err(message) => {
            if !error.is_null() {
                *error = CString::new(message).unwrap_or_default().into_raw();
            }
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn kudroid_pairing_description(session: *const PairingSession) -> *const c_char {
    session.as_ref().map_or(std::ptr::null(), |s| s.description.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn kudroid_pairing_poll(session: *const PairingSession) -> *mut c_char {
    let Some(session) = session.as_ref() else { return std::ptr::null_mut(); };
    let Ok(mut events) = session.events.lock() else { return std::ptr::null_mut(); };
    events.pop_front().and_then(|e| CString::new(e.to_string()).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub unsafe extern "C" fn kudroid_pairing_stop(session: *mut PairingSession) {
    if session.is_null() { return; }
    let mut session = Box::from_raw(session);
    if let Some(cancel) = session.cancel.take() { let _ = cancel.send(()); }
}

#[no_mangle]
pub unsafe extern "C" fn kudroid_pairing_string_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}
