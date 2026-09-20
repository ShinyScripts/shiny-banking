(() => {
    const overlay = document.getElementById('overlay');
    const panel = document.getElementById('panel');
    const heading = document.getElementById('heading');
    const backBtn = document.getElementById('back');
    const closeBtn = document.getElementById('close');
    const viewPin = document.getElementById('viewPin');
    const viewHome = document.getElementById('viewHome');
    const viewList = document.getElementById('viewList');
    const viewForm = document.getElementById('viewForm');
    const viewSettings = document.getElementById('viewSettings');
    const stats = document.getElementById('stats');
    const homeActions = document.getElementById('homeActions');
    const nav = document.getElementById('nav');
    const txList = document.getElementById('txList');
    const txDetail = document.getElementById('txDetail');
    const listLead = document.getElementById('listLead');
    const payAllBar = document.getElementById('payAllBar');
    const payAllLabel = document.getElementById('payAllLabel');
    const payAllBtn = document.getElementById('payAll');
    const formLead = document.getElementById('formLead');
    const amountInput = document.getElementById('amount');
    const ibanInput = document.getElementById('iban');
    const ibanField = document.getElementById('ibanField');
    const pinDots = [...document.querySelectorAll('#pinDots span')];
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'shiny-banking';

    const icons = {
        deposit: '<svg viewBox="0 0 24 24" fill="none"><path d="M12 5v10M8 9l4-4 4 4M6 19h12" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
        withdraw: '<svg viewBox="0 0 24 24" fill="none"><path d="M12 19V9M8 15l4 4 4-4M6 5h12" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
        transfer: '<svg viewBox="0 0 24 24" fill="none"><path d="M7 8h11M15 5l3 3-3 3M17 16H6M9 13l-3 3 3 3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };

    let ui = {};
    let account = {};
    let atm = false;
    let view = 'home';
    let listMode = 'mine';
    let formKind = 'deposit';
    let formSociety = false;
    let pin = '';
    let txs = [];
    let invoices = [];
    let activeId = null;
    let remembered = {};
    let busy = false;

    const t = (path) => path.split('.').reduce((value, key) => (
        value && value[key] != null ? value[key] : undefined
    ), ui);

    const esc = (value) => String(value ?? '')
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

    const fmt = (str, ...values) => {
        let out = String(str || '');
        values.forEach((value) => { out = out.replace('%s', value ?? ''); });
        return out;
    };

    const money = (n) => `$${Math.floor(Number(n) || 0).toLocaleString('cs-CZ')}`;

    const stamp = (unix) => {
        const date = new Date((Number(unix) || 0) * 1000);
        if (Number.isNaN(date.getTime()) || !unix) return '—';
        return date.toLocaleString('cs-CZ', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    };

    function applyLocale() {
        document.querySelectorAll('[data-i18n]').forEach((el) => {
            const value = t(el.dataset.i18n);
            if (typeof value === 'string') el.textContent = value;
        });
        document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
            const value = t(el.dataset.i18nPlaceholder);
            if (typeof value === 'string') el.setAttribute('placeholder', value);
        });
        document.querySelectorAll('[data-i18n-aria]').forEach((el) => {
            const value = t(el.dataset.i18nAria);
            if (typeof value === 'string') el.setAttribute('aria-label', value);
        });
    }

    async function request(name, data) {
        const res = await fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        try { return await res.json(); } catch (_) { return null; }
    }

    function closeUi() {
        overlay.classList.remove('is-open');
        overlay.setAttribute('aria-hidden', 'true');
        pin = '';
        request('close');
    }

    function setHeading(key) {
        heading.textContent = key === 'atm' ? (t('heading_atm') || 'ATM') : (t(key) || t('heading') || 'BANKA');
        backBtn.hidden = view === 'home' || view === 'pin';
    }

    function showView(name, wide, pinMode) {
        view = name;
        viewPin.hidden = name !== 'pin';
        viewHome.hidden = name !== 'home';
        viewList.hidden = name !== 'list';
        viewForm.hidden = name !== 'form';
        viewSettings.hidden = name !== 'settings';
        panel.classList.toggle('is-wide', !!wide);
        panel.classList.toggle('is-pin', !!pinMode);
        backBtn.hidden = name === 'home' || name === 'pin';
    }

    function renderStats(soc) {
        const data = soc && account.society ? account.society : account;
        const rows = soc ? [
            { label: t('society') || 'Society', value: data.name, wide: true },
            { label: t('society_balance') || 'Balance', value: money(data.money) },
            { label: t('iban') || 'IBAN', value: data.iban || '—' },
        ] : [
            { label: t('cash') || 'Cash', value: money(account.cash) },
            { label: t('bank') || 'Bank', value: money(account.bank) },
            { label: t('iban') || 'IBAN', value: account.iban || '—', wide: true },
        ];
        stats.innerHTML = rows.map((row) => `
            <div class="stat${row.wide ? ' is-wide' : ''}"><span>${esc(row.label)}</span><b>${esc(row.value)}</b></div>
        `).join('');
    }

    function actionCard(id, hint) {
        return `<button class="cat" type="button" data-act="${id}">
            <span class="cat-icon" aria-hidden="true">${icons[id]}</span>
            <span class="cat-copy">
                <span class="cat-name">${esc(t(id) || id)}</span>
                <span class="cat-hint">${esc(hint || '')}</span>
            </span>
        </button>`;
    }

    function renderHome(soc) {
        formSociety = !!soc;
        renderStats(soc);
        homeActions.innerHTML = [
            actionCard('deposit'),
            actionCard('withdraw'),
            actionCard('transfer'),
        ].join('');
        const chips = [
            { id: 'overview', label: t('overview') },
            { id: 'transactions', label: t('transactions') },
        ];
        if (!atm && account.hasBilling) chips.push({ id: 'invoices', label: t('invoices') });
        if (!atm && account.society) chips.push({ id: 'society', label: t('society') });
        if (!atm) chips.push({ id: 'settings', label: t('settings') });
        const active = soc ? 'society' : 'overview';
        nav.innerHTML = chips.map((chip) => `
            <button class="chip${chip.id === active ? ' is-active' : ''}" type="button" data-nav="${chip.id}">${esc(chip.label || chip.id)}</button>
        `).join('');
        heading.textContent = atm ? (t('heading_atm') || 'ATM') : (t('heading') || 'BANKA');
        showView('home', false);
    }

    function typeLabel(type) {
        return t(`type_${type}`) || type;
    }

    function renderTxs() {
        if (!txs.length) {
            txList.innerHTML = `<p class="empty">${esc(t('empty') || '')}</p>`;
        } else {
            txList.innerHTML = txs.map((row) => `
                <button class="tx${Number(row.id) === Number(activeId) ? ' is-active' : ''}" type="button" data-id="${esc(row.id)}">
                    <span class="tx-top"><span>${esc(typeLabel(row.type))}</span><span>${esc(stamp(row.created_unix))}</span></span>
                    <span class="tx-title">${esc(money(row.value))}</span>
                    <span class="tx-meta">${esc(row.sender_name)} → ${esc(row.receiver_name)}</span>
                </button>
            `).join('');
        }
        const selected = txs.find((row) => Number(row.id) === Number(activeId));
        if (!selected) {
            activeId = null;
            txDetail.innerHTML = `<p class="empty">${esc(t('none') || '')}</p>`;
            return;
        }
        txDetail.innerHTML = `
            <h2>${esc(typeLabel(selected.type))}</h2>
            <div class="kv">
                <div class="kv-row"><span>${esc(t('amount') || 'Amount')}</span><b>${esc(money(selected.value))}</b></div>
                <div class="kv-row"><span>${esc(t('from') || 'From')}</span><b>${esc(selected.sender_name)}</b></div>
                <div class="kv-row"><span>${esc(t('to') || 'To')}</span><b>${esc(selected.receiver_name)}</b></div>
                <div class="kv-row"><span>${esc(stamp(selected.created_unix))}</span><b></b></div>
            </div>
        `;
    }

    async function openList(society) {
        listMode = society ? 'society' : 'mine';
        busy = true;
        const rows = await request('transactions', { society: !!society });
        busy = false;
        txs = Array.isArray(rows) ? rows : [];
        activeId = remembered[listMode] || null;
        listLead.textContent = t('transactions_lead') || '';
        heading.textContent = t('transactions') || 'History';
        showView('list', true);
        payAllBar.hidden = true;
        renderTxs();
    }

    function invoiceTotal(inv) {
        return (Number(inv.invoice_value) || 0) + (Number(inv.fees_amount) || 0);
    }

    function unpaidSum() {
        return invoices.reduce((sum, inv) => sum + invoiceTotal(inv), 0);
    }

    function renderInvoices() {
        if (!invoices.length) {
            txList.innerHTML = `<p class="empty">${esc(t('empty_invoices') || '')}</p>`;
        } else {
            txList.innerHTML = invoices.map((inv) => `
                <button class="tx${Number(inv.id) === Number(activeId) ? ' is-active' : ''}" type="button" data-id="${esc(inv.id)}">
                    <span class="tx-top"><span>${esc(inv.ref_id)}</span><span>${esc(money(invoiceTotal(inv)))}</span></span>
                    <span class="tx-title">${esc(inv.item)}</span>
                    <span class="tx-meta">${esc(inv.author_name || inv.society_name || '')}</span>
                </button>
            `).join('');
        }
        const selected = invoices.find((inv) => Number(inv.id) === Number(activeId));
        if (!selected) {
            activeId = null;
            txDetail.innerHTML = `<p class="empty">${esc(t('none_invoice') || '')}</p>`;
        } else {
            const fees = Number(selected.fees_amount) || 0;
            txDetail.innerHTML = `
                <h2>${esc(selected.item)}</h2>
                <div class="kv">
                    <div class="kv-row"><span>${esc(t('reference') || 'Ref')}</span><b>${esc(selected.ref_id)}</b></div>
                    <div class="kv-row"><span>${esc(t('author') || 'From')}</span><b>${esc(selected.author_name)}</b></div>
                    ${selected.society_name ? `<div class="kv-row"><span>${esc(t('society') || 'Society')}</span><b>${esc(selected.society_name)}</b></div>` : ''}
                    <div class="kv-row"><span>${esc(t('due') || 'Due')}</span><b>${esc(stamp(selected.due_unix))}</b></div>
                    ${fees ? `<div class="kv-row"><span>${esc(t('fees') || 'Fees')}</span><b>${esc(money(fees))}</b></div>` : ''}
                    <div class="kv-row"><span>${esc(t('amount') || 'Amount')}</span><b>${esc(money(invoiceTotal(selected)))}</b></div>
                </div>
                ${selected.notes ? `<p class="notes">${esc(selected.notes)}</p>` : ''}
                <div class="actions">
                    <button class="btn btn-primary" type="button" data-act="pay">${esc(t('pay') || 'Pay')}</button>
                </div>
            `;
        }
        const canPayAll = invoices.length > 0;
        payAllBar.hidden = !canPayAll;
        if (canPayAll) {
            payAllLabel.textContent = fmt(t('pending') || '%s', money(unpaidSum()));
        }
    }

    async function openInvoices() {
        listMode = 'invoices';
        busy = true;
        const rows = await request('invoices');
        busy = false;
        invoices = Array.isArray(rows) ? rows : [];
        activeId = remembered.invoices || null;
        listLead.textContent = t('invoices_lead') || '';
        heading.textContent = t('invoices') || 'Invoices';
        showView('list', true);
        renderInvoices();
    }

    function openForm(kind) {
        formKind = kind;
        amountInput.value = '';
        ibanInput.value = '';
        ibanField.hidden = kind !== 'transfer';
        formLead.textContent = t(kind) || kind;
        heading.textContent = t(kind) || kind;
        showView('form', false);
    }

    function syncSettings() {
        const ibanEl = document.getElementById('newIban');
        const pinEl = document.getElementById('newPin');
        const ibanVal = (ibanEl.value || '').trim().toUpperCase();
        const pinVal = (pinEl.value || '').trim();
        const currentIban = String(account.iban || '').toUpperCase();
        document.getElementById('saveIban').disabled = !ibanVal || ibanVal === currentIban;
        document.getElementById('savePin').disabled = !/^\d{4}$/.test(pinVal);
        document.getElementById('buyCard').disabled = !!account.hasCard;
    }

    function openSettings() {
        document.getElementById('newIban').value = '';
        document.getElementById('newPin').value = '';
        document.getElementById('saveIban').textContent = fmt(t('change_iban') || '%s', money(account.ibanCost));
        document.getElementById('savePin').textContent = fmt(t('change_pin') || '%s', account.hasPin ? money(account.pinCost) : '$0');
        document.getElementById('buyCard').textContent = fmt(t('buy_cc') || '%s', money(account.cardPrice));
        heading.textContent = t('settings') || 'Settings';
        showView('settings', false);
        syncSettings();
    }

    function setPinDots() {
        pinDots.forEach((dot, index) => dot.classList.toggle('is-on', index < pin.length));
    }

    homeActions.addEventListener('click', (event) => {
        const btn = event.target.closest('[data-act]');
        if (!btn) return;
        openForm(btn.dataset.act);
    });

    nav.addEventListener('click', (event) => {
        const btn = event.target.closest('[data-nav]');
        if (!btn || busy) return;
        const id = btn.dataset.nav;
        if (id === 'overview') renderHome(false);
        else if (id === 'society') renderHome(true);
        else if (id === 'transactions') openList(formSociety);
        else if (id === 'invoices') openInvoices();
        else if (id === 'settings') openSettings();
    });

    backBtn.addEventListener('click', () => {
        if (view === 'list' && listMode === 'society') {
            renderHome(true);
            return;
        }
        renderHome(false);
    });

    closeBtn.addEventListener('click', closeUi);

    txList.addEventListener('click', (event) => {
        const btn = event.target.closest('[data-id]');
        if (!btn) return;
        activeId = Number(btn.dataset.id);
        remembered[listMode] = activeId;
        if (listMode === 'invoices') renderInvoices();
        else renderTxs();
    });

    txDetail.addEventListener('click', async (event) => {
        const btn = event.target.closest('[data-act="pay"]');
        if (!btn || busy || listMode !== 'invoices' || !activeId) return;
        busy = true;
        const result = await request('payInvoice', { id: activeId });
        busy = false;
        if (!result || !result.account) return;
        account = result.account;
        invoices = Array.isArray(result.invoices) ? result.invoices : [];
        if (!invoices.some((inv) => Number(inv.id) === Number(activeId))) activeId = null;
        remembered.invoices = activeId;
        renderInvoices();
    });

    payAllBtn.addEventListener('click', async () => {
        if (busy || listMode !== 'invoices' || !invoices.length) return;
        busy = true;
        const result = await request('payAllInvoices');
        busy = false;
        if (!result || !result.account) return;
        account = result.account;
        invoices = Array.isArray(result.invoices) ? result.invoices : [];
        activeId = null;
        remembered.invoices = null;
        renderInvoices();
    });

    document.getElementById('moneyForm').addEventListener('submit', async (event) => {
        event.preventDefault();
        if (busy) return;
        const payload = {
            amount: Number(amountInput.value),
            iban: ibanInput.value.trim(),
            society: formSociety,
        };
        busy = true;
        const result = await request(formKind, payload);
        busy = false;
        if (result && result.iban) {
            account = result;
            renderHome(formSociety);
        }
    });

    document.getElementById('newIban').addEventListener('input', syncSettings);
    document.getElementById('newPin').addEventListener('input', syncSettings);

    document.getElementById('saveIban').addEventListener('click', async () => {
        if (busy || document.getElementById('saveIban').disabled) return;
        busy = true;
        const result = await request('settings', { action: 'iban', value: document.getElementById('newIban').value });
        busy = false;
        if (result && result.iban) {
            account = result;
            openSettings();
        }
    });

    document.getElementById('savePin').addEventListener('click', async () => {
        if (busy || document.getElementById('savePin').disabled) return;
        busy = true;
        const result = await request('settings', { action: 'pin', value: document.getElementById('newPin').value });
        busy = false;
        if (result && result.iban) {
            account = result;
            openSettings();
        }
    });

    document.getElementById('buyCard').addEventListener('click', async () => {
        if (busy || document.getElementById('buyCard').disabled) return;
        busy = true;
        const result = await request('settings', { action: 'card' });
        busy = false;
        if (result && result.iban) {
            account = result;
            openSettings();
        }
    });

    document.getElementById('pinPad').addEventListener('click', async (event) => {
        const btn = event.target.closest('[data-key]');
        if (!btn || busy) return;
        const key = btn.dataset.key;
        if (key === 'C') {
            pin = '';
            setPinDots();
            return;
        }
        if (key === 'OK') {
            if (pin.length !== 4) return;
            busy = true;
            const ok = await request('unlockAtm', { pin });
            busy = false;
            pin = '';
            setPinDots();
            if (!ok) return;
            return;
        }
        if (pin.length >= 4) return;
        pin += key;
        setPinDots();
    });

    window.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && overlay.classList.contains('is-open')) closeUi();
    });

    window.addEventListener('message', (event) => {
        const payload = event.data || {};
        if (payload.action === 'close') {
            overlay.classList.remove('is-open');
            overlay.setAttribute('aria-hidden', 'true');
            return;
        }
        const data = payload.data || {};
        if (payload.action === 'pin') {
            ui = data.ui || ui;
            applyLocale();
            pin = '';
            setPinDots();
            overlay.classList.add('is-open');
            overlay.setAttribute('aria-hidden', 'false');
            heading.textContent = t('heading_atm') || 'ATM';
            showView('pin', false, true);
            return;
        }
        if (payload.action !== 'open') return;
        ui = data.ui || ui;
        account = data.account || {};
        atm = data.atm === true;
        applyLocale();
        overlay.classList.add('is-open');
        overlay.setAttribute('aria-hidden', 'false');
        renderHome(false);
    });
})();
