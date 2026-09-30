import {createController} from './controller.mjs';
const controller = createController(chrome);
// Listeners are registered synchronously at worker evaluation. No timer, alarm,
// polling, connectNative port or service-worker keepalive.
chrome.downloads.onDeterminingFilename.addListener(controller.determine);
chrome.downloads.onChanged.addListener(delta => { void controller.changed(delta).catch(() => {}); });
chrome.downloads.onErased.addListener(id => { void controller.erased(id).catch(() => {}); });
chrome.runtime.onStartup.addListener(() => { void controller.cleanup().catch(() => {}); });
chrome.runtime.onInstalled.addListener(() => { void controller.cleanup().catch(() => {}); });
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || message?.type !== 'handshake') return false;
  void controller.handshake().then(reply);
  return true;
});
void controller.cleanup().catch(() => {});
