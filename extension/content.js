// In a call (not the waiting room) once the leave/hang-up button exists.
const inCall = () =>
  document.querySelector('button[aria-label*="Leave call" i], [jsname="CQylAd"]') !== null;

setInterval(() => {
  if (inCall()) chrome.runtime.sendMessage("in-call");
}, 10000);
