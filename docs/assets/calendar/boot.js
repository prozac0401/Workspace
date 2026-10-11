/* A classic script works with MkDocs extra_javascript and Material document$. */
(() => {
  const key = Symbol.for('workspace.calendar.boot');
  if (window[key]) { window[key](); return; }
  const moduleURL = new URL('./app.mjs', document.currentScript.src);
  const instances = new WeakMap();
  const active = new Set();
  let importing;
  async function mount() {
    for (const root of active) if (!root.isConnected) {
      instances.get(root)?.destroy(); instances.delete(root); active.delete(root);
    }
    const roots = [...document.querySelectorAll('[data-workspace-calendar]')];
    if (!roots.length) return;
    try {
      importing ||= import(moduleURL.href);
      const { initCalendar } = await importing;
      for (const root of roots) if (root.isConnected && !instances.has(root)) {
        instances.set(root, initCalendar(root)); active.add(root);
      }
    } catch {
      for (const root of roots) {
        const status = root.querySelector('#status');
        if (status) { status.textContent = '달력 화면을 준비하지 못했습니다. 페이지를 새로고침해 주세요.'; status.dataset.state = 'error'; }
      }
    }
  }
  window[key] = mount;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true });
  else mount();
  if (typeof document$ !== 'undefined' && typeof document$.subscribe === 'function') document$.subscribe(mount);
})();
