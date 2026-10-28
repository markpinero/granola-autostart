importScripts("config.js");

chrome.runtime.onMessage.addListener((msg) => {
  if (msg !== "in-call") return;
  fetch("http://127.0.0.1:47615/meet", {
    method: "POST",
    headers: { "X-Autostart-Token": TOKEN },
  }).catch(() => {}); // app not running: nothing to do
});
