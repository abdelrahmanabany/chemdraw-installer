#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::io::{BufRead, BufReader};
use tauri::Emitter;

const PACK_URL: &str =
    "https://minio-oowggsgc8c88c8ogkcw80ssc.cloud.buildn.tech/chemdraw/pack.zip";

// install.sh / windows.ps1 are embedded at compile time from the repo root,
// so the app can never drift out of sync with the scripts.
const INSTALL_SH: &str = include_str!("../../../install.sh");
const INSTALL_PS1: &str = include_str!("../../../scripts/windows.ps1");

#[derive(Clone, Serialize)]
struct LogLine {
    line: String,
}

#[derive(Clone, Serialize)]
struct Done {
    code: i32,
}

fn emit(app: &tauri::AppHandle, line: String) {
    let _ = app.emit("install-log", LogLine { line });
}

/// Fire-and-forget: the install runs on a worker thread, the UI just streams logs.
#[tauri::command]
fn install_chemdraw(app: tauri::AppHandle) -> Result<(), String> {
    std::thread::spawn(move || run_install(app));
    Ok(())
}

fn run_install(app: tauri::AppHandle) {
    let workdir = std::env::temp_dir().join("chemdraw-installer");
    if let Err(e) = std::fs::create_dir_all(&workdir) {
        emit(&app, format!("ERROR: cannot write temp dir: {e}"));
        let _ = app.emit("install-done", Done { code: 1 });
        return;
    }

    let (prog, args): (&str, Vec<String>) = if cfg!(windows) {
        let script = workdir.join("install.ps1");
        if let Err(e) = std::fs::write(&script, INSTALL_PS1) {
            emit(&app, format!("ERROR: {e}"));
            let _ = app.emit("install-done", Done { code: 1 });
            return;
        }
        (
            "powershell",
            vec![
                "-NoProfile".into(),
                "-ExecutionPolicy".into(),
                "Bypass".into(),
                "-File".into(),
                script.to_string_lossy().into_owned(),
                PACK_URL.into(),
            ],
        )
    } else {
        let script = workdir.join("install.sh");
        if let Err(e) = std::fs::write(&script, INSTALL_SH) {
            emit(&app, format!("ERROR: {e}"));
            let _ = app.emit("install-done", Done { code: 1 });
            return;
        }
        (
            "sh",
            vec![
                script.to_string_lossy().into_owned(),
                PACK_URL.into(),
            ],
        )
    };

    emit(&app, format!("==> running: {prog} {}", args.join(" ")));

    let mut child = match std::process::Command::new(prog)
        .args(&args)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            emit(&app, format!("ERROR: failed to start installer: {e}"));
            let _ = app.emit("install-done", Done { code: 1 });
            return;
        }
    };

    // Stream both pipes; stdout lines verbatim, stderr prefixed.
    let stdout = child.stdout.take().expect("piped");
    let stderr = child.stderr.take().expect("piped");
    let a1 = app.clone();
    let t1 = std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            emit(&a1, line);
        }
    });
    let a2 = app.clone();
    let t2 = std::thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            let trimmed = line.trim_end().to_string();
            if !trimmed.is_empty() {
                emit(&a2, trimmed);
            }
        }
    });

    let code = child.wait().map(|s| s.code().unwrap_or(1)).unwrap_or(1);
    let _ = t1.join();
    let _ = t2.join();
    let _ = app.emit("install-done", Done { code });
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![install_chemdraw])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
