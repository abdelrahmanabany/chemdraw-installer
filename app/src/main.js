// Dumb installer UI: one button, log stream, fake-but-honest progress.
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const go = document.getElementById("go");
const log = document.getElementById("log");
const status = document.getElementById("status");
const fill = document.getElementById("fill");
const steps = [...document.querySelectorAll("#steps li")];

function say(line) {
  log.textContent += line + "\n";
  log.scrollTop = log.scrollHeight;
  // curl --progress-bar bleeds percentages like "  45.2%"; ride them for the bar
  const m = String(line).match(/(\d{1,3}(?:\.\d+)?)%/);
  if (m) fill.style.width = Math.min(100, parseFloat(m[1])) + "%";
  // step hints straight from install.sh's "==> ..." markers
  const s = String(line);
  if (s.includes("Installing wine") || s.includes("package manager")) mark(0);
  if (s.includes(".NET")) mark(1);
  if (s.includes("Silent-installing") || s.includes("Running ")) mark(2);
  if (s.includes("Launching ChemDraw")) { mark(3); fill.style.width = "100%"; }
}
function mark(i) { steps[i] && steps[i].classList.add("done"); }

go.addEventListener("click", async () => {
  go.disabled = true;
  log.textContent = "";
  status.textContent = "Installing — the .NET step takes ~15 min, leave it alone.";
  try {
    await invoke("install_chemdraw");
  } catch (e) {
    status.textContent = "Failed to start: " + e;
    go.disabled = false;
  }
});

listen("install-log", (e) => say(e.payload.line));
listen("install-done", (e) => {
  status.textContent = e.payload.code === 0
    ? "Done — ChemDraw should be open. Pick 'Activation code' if asked."
    : "Installer exited with code " + e.payload.code + " — scroll the log, then ask in the group chat.";
  go.disabled = false;
  go.textContent = "Run again";
});
