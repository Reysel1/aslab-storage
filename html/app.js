(() => {
  const $ = id => document.getElementById(id);
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'aslab-storage';
  const post = (name, data) => fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = name => {
    const body = window.ICONS && window.ICONS[name];
    return body ? `<svg viewBox="0 0 24 24">${body}</svg>` : '';
  };

  const $panel = $('panel');
  const $main = document.querySelector('.ssf-main');
  const $card = document.querySelector('.ssf-card');
  const $tabs = $('p-tabs');
  const $list = $('p-list');

  let strings = {};
  let view = null;
  let shape = '';
  let holding = null;
  let queued = null;
  const drafts = {};

  const draftKey = slot => `${view ? view.key : ''}:${slot}`;

  function shapeOf(v) {
    return JSON.stringify([v.key, v.body.layout, v.tabs.map(t => t.id), v.body.items.map(i => [
      i.label, i.count, !!i.img, !!i.use, i.progress != null, i.action ? [i.action.type, i.action.label, i.action.max] : 0,
    ])]);
  }

  function actionHtml(a, slot) {
    if (!a) return '';
    if (a.type === 'code') {
      const value = drafts[draftKey(slot)] || '';
      return `<div class="ssf-act is-inline"><input class="sl-input" data-kind="code" maxlength="4" inputmode="numeric" placeholder="${esc(strings.code || '')}" value="${esc(value)}">` +
        `<button class="sl-btn sl-btn--sm ssf-go">${esc(a.label)}</button></div>`;
    }
    if (a.type === 'amount') {
      const value = drafts[draftKey(slot)] || a.value || a.min || 1;
      return `<div class="ssf-act is-inline"><span class="sl-stepper"><button data-step="-1">−</button>` +
        `<input type="number" data-kind="amount" min="${a.min || 1}" max="${a.max || 1}" value="${esc(value)}">` +
        `<button data-step="1">+</button></span><button class="sl-btn sl-btn--sm ssf-go">${esc(a.label)}</button></div>`;
    }
    if (a.type === 'hold') {
      return `<div class="ssf-act"><button class="sl-hold${a.danger ? ' sl-hold--danger' : ''}" data-hold="${a.time || 1000}">` +
        `<i class="sl-hold-fill"></i><span class="sl-hold-text">${esc(a.label)}</span></button></div>`;
    }
    return `<div class="ssf-act is-inline"><button class="sl-btn sl-btn--sm ssf-go">${esc(a.label)}</button></div>`;
  }

  function classes(i) {
    return [i.use ? 'is-use' : '', i.tone ? `tone-${i.tone}` : '', i.on ? 'is-on' : ''].join(' ');
  }

  function rowHtml(i, slot) {
    const visual = i.img ? `<img src="${esc(i.img)}" alt="">` : icon(i.icon);
    const wide = i.action && i.action.type === 'hold';
    return `<div class="sl-box ssf-row ${classes(i)}" data-slot="${slot}">` +
      `<span class="ssf-ico">${visual}</span>` +
      `<div class="ssf-txt"><b data-f="label">${esc(i.label)}</b><small data-f="description">${esc(i.description || '')}</small></div>` +
      `${wide ? '<span></span>' : actionHtml(i.action, slot) || '<span></span>'}` +
      `${i.tag != null ? `<span class="sl-tag" data-f="tag">${esc(i.tag)}</span>` : '<span></span>'}` +
      `${i.progress != null ? `<div class="sl-progress ssf-bar" style="--value:${i.progress}%"><i></i></div>` : ''}` +
      `${wide ? actionHtml(i.action, slot) : ''}</div>`;
  }

  function itemHtml(i, slot) {
    const visual = i.img ? `<img src="${esc(i.img)}" alt="">` : icon(i.icon || 'package');
    return `<div class="sl-box ssf-item ${classes(i)}" data-slot="${slot}">` +
      `<div class="ssf-thumb">${visual}</div>` +
      `${i.count != null ? `<span class="sl-tag sl-tag--dark ssf-count">x${esc(i.count)}</span>` : ''}` +
      `<div class="ssf-txt"><b data-f="label">${esc(i.label)}</b><small data-f="description">${esc(i.description || '')}</small></div>` +
      `${i.tag != null ? `<span class="sl-tag" data-f="tag">${esc(i.tag)}</span>` : ''}` +
      `${actionHtml(i.action, slot)}</div>`;
  }

  function header(v) {
    $('p-title').textContent = v.title || '';
    $('p-sub').textContent = v.subtitle || '';
    $('p-close').innerHTML = icon('x');
    $('p-close').title = strings.close || '';
    $('p-body-title').textContent = v.body.title || '';
    const meter = v.body.meter || {};
    $('p-meter').textContent = meter.text || '';
    $('p-meter').hidden = !meter.text;
    const bar = $('p-meter-bar');
    bar.hidden = meter.value == null;
    bar.style.setProperty('--value', `${meter.value || 0}%`);
  }

  function patch(v) {
    header(v);
    v.body.items.forEach((i, n) => {
      const el = $list.querySelector(`[data-slot="${n + 1}"]`);
      if (!el) return;
      el.className = `sl-box ${v.body.layout === 'grid' ? 'ssf-item' : 'ssf-row'} ${classes(i)}`;
      const set = (f, value) => { const t = el.querySelector(`[data-f="${f}"]`); if (t) t.textContent = value == null ? '' : value; };
      set('label', i.label);
      set('description', i.description);
      set('tag', i.tag);
      const bar = el.querySelector('.ssf-bar');
      if (bar) bar.style.setProperty('--value', `${i.progress || 0}%`);
    });
  }

  function render(v) {
    const next = shapeOf(v);
    const same = view && next === shape;
    view = v;
    if (same) return patch(v);
    shape = next;
    header(v);
    $main.classList.toggle('is-single', v.tabs.length === 0);
    $card.classList.toggle('is-compact', v.tabs.length === 0);
    $tabs.hidden = v.tabs.length === 0;
    $tabs.innerHTML = v.tabs.map(t => `<button class="ssf-tab${t.active ? ' is-active' : ''}" data-tab="${esc(t.id)}">` +
      `${icon(t.icon)}<span>${esc(t.label)}</span>${t.badge ? `<small class="sl-tag">${esc(t.badge)}</small>` : ''}</button>`).join('');
    const grid = v.body.layout === 'grid';
    const top = $list.dataset.key === v.key ? $list.scrollTop : 0;
    $list.dataset.key = v.key;
    $list.classList.toggle('is-grid', grid);
    $list.innerHTML = v.body.items.map((i, n) => (grid ? itemHtml : rowHtml)(i, n + 1)).join('');
    $list.scrollTop = top;
  }

  function show(v) {
    if (holding) { queued = v; return; }
    render(v);
    $panel.hidden = false;
  }

  function hide() {
    $panel.hidden = true;
    view = null;
    shape = '';
    queued = null;
  }

  const slotOf = el => Number(el.closest('[data-slot]').dataset.slot);

  function send(el) {
    const box = el.closest('.ssf-act');
    const input = box && box.querySelector('input');
    const slot = slotOf(el);
    const value = input ? input.value : undefined;
    if (input && input.dataset.kind === 'code') {
      if (!/^\d{4}$/.test(value)) { input.focus(); input.classList.add('is-error'); return; }
      delete drafts[draftKey(slot)];
      input.value = '';
    }
    post('ssf:action', { slot, value });
  }

  $tabs.addEventListener('click', e => {
    const b = e.target.closest('[data-tab]');
    if (b && !b.classList.contains('is-active')) post('ssf:tab', { id: b.dataset.tab });
  });

  $list.addEventListener('click', e => {
    const step = e.target.closest('[data-step]');
    if (step) {
      const input = step.parentElement.querySelector('input');
      const min = Number(input.min) || 1;
      const max = Number(input.max) || min;
      input.value = Math.max(min, Math.min(max, (Number(input.value) || min) + Number(step.dataset.step)));
      drafts[draftKey(slotOf(input))] = input.value;
      return;
    }
    const go = e.target.closest('.ssf-go');
    if (go) return send(go);
    if (e.target.closest('.ssf-act')) return;
    const row = e.target.closest('.is-use');
    if (row) post('ssf:use', { slot: slotOf(row) });
  });

  $list.addEventListener('input', e => {
    const input = e.target;
    if (input.dataset.kind === 'code') input.value = input.value.replace(/\D/g, '').slice(0, 4);
    if (input.dataset.kind === 'amount') {
      const max = Number(input.max) || 1;
      if (Number(input.value) > max) input.value = max;
    }
    input.classList.remove('is-error');
    drafts[draftKey(slotOf(input))] = input.value;
  });

  $list.addEventListener('keydown', e => {
    if (e.key === 'Enter' && e.target.matches('input')) send(e.target);
  });

  $list.addEventListener('pointerdown', e => {
    const btn = e.target.closest('.sl-hold');
    if (!btn || holding) return;
    const duration = Number(btn.dataset.hold) || 1000;
    const text = btn.querySelector('.sl-hold-text');
    const label = text.textContent;
    const t0 = performance.now();
    const state = { btn, cancel: null };
    holding = state;
    text.textContent = strings.hold || label;
    let raf = 0;
    const finish = done => {
      cancelAnimationFrame(raf);
      btn.style.setProperty('--hold', 0);
      text.textContent = label;
      btn.removeEventListener('pointerup', stop);
      btn.removeEventListener('pointerleave', stop);
      holding = null;
      if (done) {
        btn.classList.add('is-done');
        post('ssf:action', { slot: slotOf(btn) });
      }
      if (queued) { const v = queued; queued = null; render(v); }
    };
    const stop = () => finish(false);
    const tick = t => {
      const p = Math.min(1, (t - t0) / duration);
      btn.style.setProperty('--hold', p);
      if (p >= 1) return finish(true);
      raf = requestAnimationFrame(tick);
    };
    btn.addEventListener('pointerup', stop);
    btn.addEventListener('pointerleave', stop);
    raf = requestAnimationFrame(tick);
  });

  $('p-close').addEventListener('click', () => post('ssf:close'));

  window.addEventListener('keydown', e => {
    if (e.key === 'Escape' && !$panel.hidden) post('ssf:close');
  });

  window.addEventListener('message', e => {
    const m = e.data || {};
    if (m.strings) strings = m.strings;
    if (m.action === 'panel') m.open ? show(m.view) : hide();
  });
})();
