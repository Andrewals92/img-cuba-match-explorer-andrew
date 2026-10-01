(() => {
  "use strict";
  const q = (id) => document.getElementById(id),
    qa = (s) => Array.from(document.querySelectorAll(s));
  const CONFIG = window.IMG_CUBA_CLOUD || {};
  const CLOUD = {
    url: String(CONFIG.url || "").replace(/\/$/, ""),
    anonKey: String(CONFIG.anonKey || ""),
  };
  const AUTH_REDIRECT = location.origin + location.pathname;
  const SESSION_KEY = "img_cuba_session_v2",
    DEMO_KEY = "img_cuba_demo_v2";
  let session = readJSON(SESSION_KEY),
    recoveryMode = false,
    adminUserIndex = new Map(),
    seenNotifications = null,
    programCache = new Map(),
    profile = null,
    currentView = "dashboard",
    publicDB = {
      programs: [],
      overview: null,
      programStats: [],
      recent: [],
      matchStates: [],
      matchPrograms: [],
    },
    myDB = { cycles: [], reports: [] },
    intelDB = {
      specialties: [],
      official: [],
      sources: new Map(),
      watches: [],
      notifications: [],
    };
  const DEMO_PROGRAMS = [
    {
      id: "demo1",
      acgme_program_id: "DEMO-001",
      name: "Demo Miami Academic Medical Center",
      institution: "Demo Health System",
      specialty: "Internal Medicine",
      city: "Miami",
      state: "FL",
    },
    {
      id: "demo2",
      acgme_program_id: "DEMO-002",
      name: "Demo South Florida Community Hospital",
      institution: "Demo Community Health",
      specialty: "Internal Medicine",
      city: "Hialeah",
      state: "FL",
    },
    {
      id: "demo3",
      acgme_program_id: "DEMO-003",
      name: "Demo Orlando Regional Program",
      institution: "Demo Orlando Health",
      specialty: "Internal Medicine",
      city: "Orlando",
      state: "FL",
    },
    {
      id: "demo4",
      acgme_program_id: "DEMO-004",
      name: "Demo Tampa University Hospital",
      institution: "Demo University",
      specialty: "Internal Medicine",
      city: "Tampa",
      state: "FL",
    },
    {
      id: "demo5",
      acgme_program_id: "DEMO-005",
      name: "Demo Northeast Teaching Hospital",
      institution: "Demo Medical Group",
      specialty: "Internal Medicine",
      city: "New York",
      state: "NY",
    },
  ];
  let demo = readJSON(DEMO_KEY) || {
    cycles: [
      {
        id: "dc1",
        anonId: "DEMO-CUBA-01",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2018,
        step2: 238,
        usce: 6,
        lors: 3,
        visa: false,
        consentPublic: true,
      },
      {
        id: "dc2",
        anonId: "DEMO-CUBA-02",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2020,
        step2: 246,
        usce: 8,
        lors: 4,
        visa: false,
        consentPublic: true,
      },
      {
        id: "dc3",
        anonId: "DEMO-CUBA-03",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2019,
        step2: 231,
        usce: 5,
        lors: 3,
        visa: true,
        consentPublic: true,
      },
      {
        id: "dc4",
        anonId: "DEMO-CUBA-04",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2017,
        step2: 226,
        usce: 7,
        lors: 3,
        visa: false,
        consentPublic: true,
      },
      {
        id: "dc5",
        anonId: "DEMO-CUBA-05",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2021,
        step2: 252,
        usce: 9,
        lors: 4,
        visa: true,
        consentPublic: true,
      },
      {
        id: "dc6",
        anonId: "DEMO-CUBA-06",
        cycle: 2027,
        specialty: "Internal Medicine",
        yog: 2016,
        step2: 223,
        usce: 4,
        lors: 3,
        visa: false,
        consentPublic: true,
      },
    ],
    reports: [],
  };
  if (!Array.isArray(demo.cycles)) demo.cycles = [];
  if (!Array.isArray(demo.reports)) demo.reports = [];
  if (!demo.reports.length && demo.cycles.length) {
    DEMO_PROGRAMS.forEach((p, i) =>
      demo.cycles.forEach((c, j) => {
        if ((i + j) % 2 === 0 || i < 2)
          demo.reports.push({
            id: `dr${i}${j}`,
            applicantCycleId: c.id,
            cycle: 2027,
            programId: p.id,
            program: p.name,
            state: p.state,
            specialty: "Internal Medicine",
            applied: true,
            signal: j % 5 === 0 ? "Gold" : j % 3 === 0 ? "Silver" : "None",
            interview: i < 2 || j % 4 === 0,
            interviewDate: `2026-${String(10 + (j % 2)).padStart(2, "0")}-${String(5 + j).padStart(2, "0")}`,
            ranked: i < 2 && j % 2 === 0,
            matched: i === 0 && j < 3,
            track: "Categorical",
            retrospective: false,
            verificationStatus: j % 3 === 0 ? "verified" : "unverified",
          });
      }),
    );
  }
  function readJSON(k) {
    try {
      return JSON.parse(localStorage.getItem(k) || "null");
    } catch {
      return null;
    }
  }
  function writeJSON(k, v) {
    try {
      localStorage.setItem(k, JSON.stringify(v));
    } catch {}
  }
  function cloudReady() {
    return !!(CLOUD.url && CLOUD.anonKey);
  }
  // FIX: the new "sb_publishable_..." keys are not JWTs. Sending them as
  // "Authorization: Bearer" can be rejected, so the header is only sent when a
  // real user access token (JWT) exists. The apikey header alone is enough for
  // anonymous/public requests.
  function headers(publicOnly = false, extra = {}) {
    const h = {
      apikey: CLOUD.anonKey,
      "Content-Type": "application/json",
      ...extra,
    };
    if (!publicOnly && session?.access_token)
      h.Authorization = `Bearer ${session.access_token}`;
    else if (CLOUD.anonKey.startsWith("eyJ"))
      h.Authorization = `Bearer ${CLOUD.anonKey}`; // legacy JWT anon key
    return h;
  }
  function translateError(m) {
    const s = String(m || "");
    const map = [
      [/invalid login credentials/i, "Email o contraseña incorrectos."],
      [/email not confirmed/i, "Debes confirmar tu email antes de iniciar sesión. Revisa tu correo."],
      [/user already registered/i, "Ya existe una cuenta con ese email. Inicia sesión."],
      [/password should be at least/i, "La contraseña debe tener al menos 8 caracteres."],
      [/rate limit|too many requests|over_email_send_rate_limit/i, "Demasiados intentos. Espera unos minutos y vuelve a intentarlo."],
      [/jwt expired|invalid jwt|bad_jwt/i, "Tu sesión expiró. Inicia sesión de nuevo."],
      [/duplicate key.*program_watch/i, "Ya tienes una alerta para esa especialidad/estado."],
      [/duplicate key.*applicant_cycles|applicant_cycles_user_id_match_cycle_specialty_key/i, "Ya tienes un perfil para ese ciclo y especialidad. Edítalo en lugar de crear otro."],
      [/could not find the function|PGRST202/i, "Falta una función en la base de datos. El administrador debe ejecutar las migraciones 004 y 005 de supabase/migrations."],
      [/failed to fetch|networkerror|load failed/i, "No se pudo conectar con el servidor. Revisa tu conexión."],
    ];
    for (const [re, msg] of map) if (re.test(s)) return msg;
    return s || "Error inesperado.";
  }
  const recentToasts = new Map();
  function toast(msg, type = "good") {
    // Avoid stacking the same message over and over (e.g. on every refresh).
    const now = Date.now();
    if (recentToasts.has(msg) && now - recentToasts.get(msg) < 15000) return;
    recentToasts.set(msg, now);
    let w = document.querySelector(".toast-wrap");
    if (!w) {
      w = document.createElement("div");
      w.className = "toast-wrap";
      document.body.appendChild(w);
    }
    const d = document.createElement("div");
    d.className = `toast ${type}`;
    d.textContent = msg;
    w.appendChild(d);
    setTimeout(() => d.remove(), 4200);
  }
  async function request(
    path,
    { method = "GET", body = null, publicOnly = false, prefer = null } = {},
  ) {
    if (!cloudReady()) throw new Error("Supabase no está configurado.");
    if (!publicOnly) await ensureSession();
    const send = async () => {
      const h = headers(publicOnly);
      if (prefer) h["Prefer"] = prefer;
      const r = await fetch(CLOUD.url + path, {
        method,
        headers: h,
        body: body === null ? null : JSON.stringify(body),
      });
      let data = null;
      const text = await r.text();
      if (text) {
        try {
          data = JSON.parse(text);
        } catch {
          data = text;
        }
      }
      return { r, data };
    };
    let { r, data } = await send();
    // FIX: an expired/invalid token used to break every request until the
    // user cleared the browser. Now we refresh once and retry; if that fails
    // the local session is dropped and the user is asked to log in again.
    if (r.status === 401 && !publicOnly && session?.refresh_token) {
      const ok = await ensureSession(true);
      if (ok) ({ r, data } = await send());
      else {
        dropSession();
        ({ r, data } = await send());
      }
    }
    if (!r.ok) {
      const m =
        data?.message ||
        data?.msg ||
        data?.error_description ||
        data?.hint ||
        `HTTP ${r.status}`;
      const err = new Error(translateError(m + " " + (data?.code || "")).trim());
      err.status = r.status;
      throw err;
    }
    return data;
  }
  function dropSession() {
    session = null;
    profile = null;
    seenNotifications = null;
    try {
      localStorage.removeItem(SESSION_KEY);
    } catch {}
  }
  async function authRequest(path, body) {
    const r = await fetch(CLOUD.url + "/auth/v1" + path, {
      method: "POST",
      headers: { apikey: CLOUD.anonKey, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok)
      throw new Error(
        translateError(
          d?.msg ||
            d?.message ||
            d?.error_description ||
            d?.error_code ||
            "Error de autenticación",
        ),
      );
    return d;
  }
  // Normalizes GoTrue token responses (expires_at is not always present).
  function storeSession(d) {
    if (!d?.access_token) return false;
    const now = Math.floor(Date.now() / 1000);
    session = {
      ...d,
      expires_at: Number(d.expires_at || now + Number(d.expires_in || 3600)),
      user: d.user || session?.user || null,
    };
    writeJSON(SESSION_KEY, session);
    return true;
  }
  // FIX: several requests run in parallel (Promise.all). Each one used to fire
  // its own refresh with the same refresh_token, which Supabase can treat as
  // token reuse and revoke the session. A single shared refresh is used now.
  let refreshing = null;
  async function ensureSession(force = false) {
    if (!session?.refresh_token) return false;
    const now = Math.floor(Date.now() / 1000);
    if (!force && session.expires_at && session.expires_at - now > 90)
      return true;
    if (!refreshing) {
      refreshing = (async () => {
        try {
          const d = await authRequest("/token?grant_type=refresh_token", {
            refresh_token: session.refresh_token,
          });
          return storeSession(d);
        } catch {
          dropSession();
          return false;
        } finally {
          setTimeout(() => (refreshing = null), 0);
        }
      })();
    }
    return refreshing;
  }
  async function signup(email, password) {
    const d = await authRequest(
      "/signup?redirect_to=" + encodeURIComponent(AUTH_REDIRECT),
      { email, password },
    );
    // FIX: when email confirmation is disabled Supabase returns a session
    // immediately; it was being discarded, so the user looked logged-out.
    storeSession(d);
    return d;
  }
  async function signin(email, password) {
    const d = await authRequest("/token?grant_type=password", {
      email,
      password,
    });
    storeSession(d);
    return d;
  }
  async function updatePassword(password) {
    await ensureSession();
    const r = await fetch(CLOUD.url + "/auth/v1/user", {
      method: "PUT",
      headers: headers(),
      body: JSON.stringify({ password }),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok)
      throw new Error(
        translateError(d?.msg || d?.message || "No se pudo cambiar la contraseña."),
      );
    return d;
  }
  async function signout() {
    if (session?.access_token)
      try {
        await fetch(CLOUD.url + "/auth/v1/logout", {
          method: "POST",
          headers: headers(),
        });
      } catch {}
    dropSession();
  }
  async function authUser(accessToken) {
    const r = await fetch(CLOUD.url + "/auth/v1/user", {
      headers: {
        apikey: CLOUD.anonKey,
        Authorization: "Bearer " + accessToken,
      },
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok)
      throw new Error(
        d?.msg || d?.message || "No se pudo recuperar la sesión confirmada.",
      );
    return d;
  }
  async function consumeAuthRedirect() {
    if (!cloudReady()) return false;
    const h = new URLSearchParams(location.hash.replace(/^#/, ""));
    const qy = new URLSearchParams(location.search);
    const err =
      h.get("error_description") ||
      qy.get("error_description") ||
      h.get("error") ||
      qy.get("error");
    if (err) {
      history.replaceState({}, document.title, location.pathname);
      toast(
        /expired|otp/i.test(err)
          ? "El enlace del correo expiró o ya fue usado. Solicita uno nuevo."
          : decodeURIComponent(err.replace(/\+/g, " ")),
        "bad",
      );
      return false;
    }
    const access = h.get("access_token"),
      refresh = h.get("refresh_token");
    if (!access || !refresh) return false;
    try {
      const expiresIn = Number(h.get("expires_in") || 3600),
        expiresAt = Number(
          h.get("expires_at") || Math.floor(Date.now() / 1000) + expiresIn,
        );
      const user = await authUser(access);
      storeSession({
        access_token: access,
        refresh_token: refresh,
        token_type: h.get("token_type") || "bearer",
        expires_in: expiresIn,
        expires_at: expiresAt,
        user,
      });
      const type = h.get("type") || qy.get("type");
      history.replaceState({}, document.title, location.pathname);
      if (type === "recovery") {
        recoveryMode = true;
        currentView = "account";
        toast("Escribe tu nueva contraseña en Cuenta → Cambiar contraseña.");
      } else toast("Email confirmado. Tu sesión está activa.");
      return true;
    } catch (e) {
      toast(e.message || "No se pudo completar la confirmación.", "bad");
      return false;
    }
  }
  async function sendRecovery(email) {
    return authRequest(
      "/recover?redirect_to=" + encodeURIComponent(AUTH_REDIRECT),
      { email },
    );
  }
  function cycleVal() {
    const v = q("globalCycle").value;
    return v === "all" ? null : Number(v);
  }
  function esc(v) {
    return String(v ?? "").replace(
      /[&<>'"]/g,
      (s) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          "'": "&#39;",
          '"': "&quot;",
        })[s],
    );
  }
  function numOrNull(v) {
    if (v === "" || v === null || v === undefined) return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  function pct(a, b) {
    return b ? Math.round((a / b) * 1000) / 10 : 0;
  }
  function median(arr) {
    const a = arr
      .filter((v) => v !== null && v !== undefined && v !== "")
      .map(Number)
      .sort((x, y) => x - y);
    if (!a.length) return null;
    const m = Math.floor(a.length / 2);
    return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
  }
  function table(cols, rows) {
    if (!rows.length)
      return '<div class="empty-state">Sin datos todavía.</div>';
    return `<table class="data-table"><thead><tr>${cols.map((c) => `<th>${esc(c[0])}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${cols.map((c) => `<td>${c[2] ? c[2](r) : esc(r[c[1]] ?? "—")}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
  }
  function tag(text, cls = "") {
    return `<span class="tag ${cls}">${esc(text)}</span>`;
  }
  function specialties() {
    const s = new Map();
    const add = (x) => {
      const v = String(x || "").trim();
      if (v && !s.has(v.toLowerCase())) s.set(v.toLowerCase(), v);
    };
    add("Internal Medicine");
    (publicDB.specialtyNames || []).forEach(add);
    publicDB.programs.forEach((p) => add(p.specialty));
    publicDB.programStats.forEach((p) => add(p.specialty));
    myDB.cycles.forEach((c) => add(c.specialty));
    return [...s.values()].sort((a, b) => a.localeCompare(b));
  }
  // FIX: re-filling the selects on every refresh used to reset the user's
  // current choice. The selected value is now preserved.
  function setOptions(id, html, fallback) {
    const el = q(id);
    if (!el) return;
    const prev = el.value;
    el.innerHTML = html;
    if (prev && [...el.options].some((o) => o.value === prev)) el.value = prev;
    else if (fallback !== undefined) el.value = fallback;
  }
  function fillSpecialties() {
    const list = specialties();
    const opts = list
      .map((x) => `<option value="${esc(x)}">${esc(x)}</option>`)
      .join("");
    const all = '<option value="all">Todas las especialidades</option>';
    setOptions("programSpecialty", all + opts, "all");
    setOptions("simSpecialty", opts, "Internal Medicine");
    setOptions("interviewSpecialty", all + opts, "all");
    const dl = q("specialtyList");
    if (dl) dl.innerHTML = opts;
  }
  function normalizeCycle(c) {
    return {
      id: c.id,
      anonId: c.anon_id ?? c.anonId,
      cycle: Number(c.match_cycle ?? c.cycle),
      specialty: c.specialty,
      yog: Number(c.yog),
      step1: c.step1_status ?? c.step1,
      step1Attempts: Number(c.step1_attempts ?? c.step1Attempts ?? 0),
      step2: c.step2_ck ?? c.step2,
      step3: c.step3,
      ecfmg: c.ecfmg_status ?? c.ecfmg,
      usce: Number(c.usce_months ?? c.usce ?? 0),
      usceType: c.usce_type ?? c.usceType,
      lors: Number(c.us_lors ?? c.lors ?? 0),
      usPhysicianLors: Number(c.us_physician_lors ?? c.usPhysicianLors ?? 0),
      pdChairLor: c.pd_chair_lor ?? c.pdChairLor,
      pubs: Number(c.publications ?? c.pubs ?? 0),
      research: Number(c.research_projects ?? c.research ?? 0),
      volunteer: c.volunteer_experience ?? c.volunteer,
      visa: c.visa_required ?? c.visa,
      immigrationStatus: c.immigration_status ?? c.immigrationStatus,
      previousResidency: c.previous_residency_outside_us ?? c.previousResidency,
      geoPreference: c.geographic_preference ?? c.geoPreference,
      consentPublic: c.consent_public ?? c.consentPublic,
      programsApplied: c.programs_applied ?? c.programsApplied ?? null,
      interviewInvites: c.interview_invites ?? c.interviewInvites ?? null,
      notes: c.notes,
      missingFields: [["Step 2 CK", c.step2_ck ?? c.step2], ["YOG", c.yog], ["USCE", c.usce_months ?? c.usce], ["LoRs", c.us_lors ?? c.lors], ["visa", c.visa_required ?? c.visa], ["total de aplicaciones", c.programs_applied ?? c.programsApplied], ["total de invitaciones", c.interview_invites ?? c.interviewInvites]].filter(([,v]) => v === null || v === undefined || v === "").map(([k]) => k),
    };
  }
  function normalizeReport(r) {
    return {
      id: r.id,
      applicantCycleId: r.applicant_cycle_id ?? r.applicantCycleId,
      cycle: Number(r.match_cycle ?? r.cycle),
      programId: r.program_id ?? r.programId,
      program: r.program_name_snapshot ?? r.program_name ?? r.program,
      state: r.state_snapshot ?? r.state,
      specialty: r.specialty,
      applied: r.applied,
      signal: r.signal,
      geoPreferenceUsed: r.geo_preference_used ?? r.geoPreferenceUsed,
      interview: r.interview,
      interviewDate: r.interview_date ?? r.interviewDate,
      interviewAttended: r.interview_attended ?? r.interviewAttended,
      ranked: r.ranked,
      matched: r.matched,
      track: r.track,
      retrospective: r.retrospective,
      verificationRequested:
        r.verification_requested ?? r.verificationRequested,
      verificationStatus: r.verification_status ?? r.verificationStatus,
      verificationNote: r.verification_note ?? r.verificationNote,
      verifiedAt: r.verified_at,
    };
  }
  // FIX: the whole catalog used to be downloaded into one dropdown. Supabase
  // returns at most 1000 rows per request, so most programs never appeared.
  // Now only the specialty list is loaded up-front and programs are fetched
  // per specialty (cached) when the user picks an applicant cycle.
  async function loadPrograms() {
    if (!cloudReady()) {
      publicDB.programs = DEMO_PROGRAMS;
      publicDB.specialtyNames = [];
      return;
    }
    try {
      const s =
        (await request(
          "/rest/v1/acgme_specialties?select=name&active=eq.true&order=name.asc",
          { publicOnly: true },
        )) || [];
      publicDB.specialtyNames = s.map((x) => x.name).filter(Boolean);
    } catch {
      publicDB.specialtyNames = [];
    }
  }
  async function programsFor(spec) {
    const key = String(spec || "").trim().toLowerCase();
    if (!cloudReady())
      return DEMO_PROGRAMS.filter(
        (p) => !key || p.specialty.toLowerCase() === key,
      );
    if (!key) return [];
    if (programCache.has(key)) return programCache.get(key);
    const rows =
      (await request(
        "/rest/v1/programs?select=id,acgme_program_id,name,institution,specialty,city,state&active=eq.true&specialty=ilike." +
          encodeURIComponent(String(spec).trim().replace(/[*%_]/g, "")) +
          "&order=state.asc,name.asc&limit=1000",
        { publicOnly: true },
      )) || [];
    programCache.set(key, rows);
    return rows;
  }
  async function loadProfile() {
    if (!cloudReady() || !session?.user?.id) {
      profile = null;
      return;
    }
    try {
      const d = await request(
        `/rest/v1/profiles?id=eq.${encodeURIComponent(session.user.id)}&select=id,email,role,display_name`,
      );
      profile = d?.[0] || { role: "user", email: session.user.email };
    } catch (e) {
      profile = session ? { role: "user", email: session.user.email } : null;
      if (e.status !== 401) throw e;
    }
  }
  async function loadMyData() {
    if (!cloudReady()) {
      myDB = {
        cycles: demo.cycles.map(normalizeCycle),
        reports: demo.reports.map(normalizeReport),
      };
      return;
    }
    if (!session?.user?.id) {
      myDB = { cycles: [], reports: [] };
      return;
    }
    // FIX: administrators can read every row through RLS, so without this
    // filter "Mis datos" listed (and let the admin edit) other users' data.
    myDB = { cycles: [], reports: [] };
    const uid = encodeURIComponent(session.user.id);
    const [c, r] = await Promise.all([
      request(
        `/rest/v1/applicant_cycles?select=*&user_id=eq.${uid}&order=match_cycle.desc,created_at.desc`,
      ),
      request(
        `/rest/v1/program_reports?select=*&user_id=eq.${uid}&order=created_at.desc`,
      ),
    ]);
    myDB = {
      cycles: (c || []).map(normalizeCycle),
      reports: (r || []).map(normalizeReport),
    };
  }
  async function rpc(name, args = {}, publicOnly = true) {
    return request(`/rest/v1/rpc/${name}`, {
      method: "POST",
      body: args,
      publicOnly,
    });
  }
  function weekStart(d) {
    if (!d) return null;
    const t = new Date(d + "T00:00:00Z");
    if (isNaN(t)) return null;
    t.setUTCDate(t.getUTCDate() - ((t.getUTCDay() + 6) % 7)); // Monday
    return t.toISOString().slice(0, 10);
  }
  function computeDemoPublic() {
    const cy = cycleVal(),
      cycles = demo.cycles.filter(
        (c) => c.consentPublic && (cy === null || c.cycle === cy),
      ),
      ids = new Set(cycles.map((c) => c.id)),
      reps = demo.reports.filter(
        (r) => ids.has(r.applicantCycleId) && (cy === null || r.cycle === cy),
      );
    const interviewed = reps.filter((r) => r.interview);
    const matches = reps.filter((r) => r.matched);
    const s2c = cycles.filter((c) => c.step2 !== null && c.step2 !== undefined && c.step2 !== "");
    const by = {};
    reps.forEach((r) => {
      const k = r.program;
      by[k] ??= {
        program_name: k,
        state: r.state,
        specialty: r.specialty,
        applicants: new Set(),
        applications: 0,
        interviews: 0,
        matches: 0,
        steps: [],
        usce: [],
        lors: [],
      };
      const x = by[k],
        c = cycles.find((z) => z.id === r.applicantCycleId);
      x.applicants.add(r.applicantCycleId);
      if (r.applied) x.applications++;
      if (r.interview) x.interviews++;
      if (r.matched) x.matches++;
      if (c) {
        x.steps.push(c.step2);
        x.usce.push(c.usce);
        x.lors.push(c.lors);
      }
    });
    publicDB.programStats = Object.values(by).map((x) => ({
      ...x,
      applicants: x.applicants.size,
      interview_rate: pct(x.interviews, x.applications),
      median_step2: x.applicants.size >= 5 ? median(x.steps) : null,
      median_usce: x.applicants.size >= 5 ? median(x.usce) : null,
      median_lors: x.applicants.size >= 5 ? median(x.lors) : null,
    }));
    publicDB.overview = {
      applicants: cycles.length,
      applications: reps.filter((r) => r.applied).length,
      programs: new Set(reps.map((r) => r.program)).size,
      interviews: interviewed.length,
      matches: matches.length,
      step_bins: [
        { label: "≤220", count: s2c.filter((c) => c.step2 <= 220).length },
        {
          label: "221–230",
          count: s2c.filter((c) => c.step2 > 220 && c.step2 <= 230).length,
        },
        {
          label: "231–240",
          count: s2c.filter((c) => c.step2 > 230 && c.step2 <= 240).length,
        },
        {
          label: "241–250",
          count: s2c.filter((c) => c.step2 > 240 && c.step2 <= 250).length,
        },
        { label: "251+", count: s2c.filter((c) => c.step2 > 250).length },
      ],
    };
    const weekly = {};
    interviewed.filter((r) => r.interviewDate).forEach((r) => {
      const wk = weekStart(r.interviewDate) || "—";
      const k = r.program + "|" + wk;
      weekly[k] ??= {
        program_name: r.program,
        specialty: r.specialty,
        week_start: wk,
        reports: 0,
        verified: 0,
      };
      weekly[k].reports++;
      if (r.verificationStatus === "verified") weekly[k].verified++;
    });
    publicDB.recent = Object.values(weekly).filter((x) => x.reports >= 3);
    const states = {};
    matches.forEach((r) => (states[r.state] = (states[r.state] || 0) + 1));
    publicDB.matchStates = Object.entries(states).map(([state, matches]) => ({
      state,
      matches,
    }));
    publicDB.matchPrograms = Object.values(by)
      .filter((x) => x.matches >= 3)
      .map((x) => ({
        program_name: x.program_name,
        state: x.state,
        matches: x.matches,
      }));
  }
  async function loadPublic() {
    if (!cloudReady()) {
      computeDemoPublic();
      return;
    }
    const cy = cycleVal();
    // FIX: Promise.all meant that a single failing RPC (e.g. program_stats,
    // which could not be created by the original schema.sql) wiped out the
    // whole dashboard. Each block now loads independently.
    const res = await Promise.allSettled([
      rpc("community_overview", { p_cycle: cy }),
      rpc("program_stats", { p_cycle: cy, p_specialty: null }),
      rpc("recent_interview_activity", { p_cycle: cy, p_specialty: null }),
      rpc("match_state_stats", { p_cycle: cy }),
      rpc("match_program_stats", { p_cycle: cy }),
    ]);
    const val = (i, d) =>
      res[i].status === "fulfilled" ? res[i].value ?? d : d;
    publicDB.overview = val(0, null);
    publicDB.programStats = val(1, []);
    publicDB.recent = val(2, []);
    publicDB.matchStates = val(3, []);
    publicDB.matchPrograms = val(4, []);
    const failed = res.find((x) => x.status === "rejected");
    if (failed) throw failed.reason;
  }
  function renderStatus() {
    const ready = cloudReady();
    q("cloudBadge").textContent = ready ? "COMMUNITY CLOUD" : "DEMO / SETUP";
    q("cloudBadge").className = "pill status " + (ready ? "cloud" : "demo");
    q("modeBanner").className = "demo-banner " + (ready ? "cloud" : "");
    q("modeBanner").textContent = ready
      ? "Community Cloud activo • Los datos guardados se almacenan de forma persistente en Supabase y están protegidos por RLS."
      : "Modo demostración • Los datos se guardan solo en este navegador. Para producción, configura Supabase una vez en cloud-config.js.";
    q("heroCycle").textContent =
      q("globalCycle").value === "all" ? "ALL" : q("globalCycle").value;
    q("backendStatus").innerHTML =
      `<div class="backend-line"><span>Supabase</span>${tag(ready ? "Configurado" : "No configurado", ready ? "good" : "warn")}</div><div class="backend-line"><span>Persistencia multi-dispositivo</span>${tag(ready ? "Activa" : "Solo demo local", ready ? "good" : "warn")}</div><div class="backend-line"><span>Sesión</span>${tag(session ? "Autenticado" : "Sin sesión", session ? "good" : "")}</div>`;
  }
  function renderDashboard() {
    const o = publicDB.overview || {};
    const items = [
      ["Applicants", o.applicants || 0],
      ["Applications", o.applications || 0],
      ["Programs", o.programs || 0],
      ["Interviews", o.interviews || 0],
      ["Matches", o.matches || 0],
    ];
    q("kpiGrid").innerHTML = items
      .map(
        ([a, b]) =>
          `<div class="kpi"><span>${a}</span><strong>${b}</strong></div>`,
      )
      .join("");
    const tops = [...publicDB.programStats]
        .sort((a, b) => (b.interviews || 0) - (a.interviews || 0))
        .slice(0, 7),
      max = Math.max(1, ...tops.map((x) => x.interviews || 0));
    q("programBars").innerHTML = tops.length
      ? tops
          .map(
            (x) =>
              `<div class="bar-row"><div class="label">${workspace.programLink(x)}</div><div class="bar-track"><div class="bar-fill" style="width:${((x.interviews || 0) / max) * 100}%"></div></div><b>${x.interviews || 0}</b></div>`,
          )
          .join("")
      : '<div class="empty-state">Aún no hay entrevistas agregadas.</div>';
    const bins = o.step_bins || o.stepBins || [];
    const mb = Math.max(1, ...bins.map((x) => x.count || 0));
    q("scoreDistribution").innerHTML = bins.length
      ? bins
          .map(
            (x) =>
              `<div class="dist-col"><div class="dist-bar" style="height:${Math.max(5, ((x.count || 0) / mb) * 120)}px"></div><small>${esc(x.label)}<br>${x.count || 0}</small></div>`,
          )
          .join("")
      : '<div class="empty-state">Se mostrará cuando haya datos suficientes.</div>';
    q("recentActivity").innerHTML = publicDB.recent.length
      ? publicDB.recent
          .slice(0, 12)
          .map(
            (x) =>
              `<div class="activity"><div><strong>${workspace.programLink(x)}</strong><span>${esc(x.week_start)} • ${x.reports} reportes</span></div>${tag(`${x.verified || 0} verified`, "good")}</div>`,
          )
          .join("")
      : '<div class="empty-state">No hay grupos recientes que alcancen el umbral de privacidad.</div>';
  }
  function renderPrograms() { workspace.renderPrograms(); }
  function renderInterviews() {
    const term = q("interviewSearch").value.toLowerCase(),
      spec = q("interviewSpecialty").value;
    const rows = publicDB.recent.filter(
      (x) =>
        (spec === "all" || x.specialty === spec) &&
        (!term || x.program_name.toLowerCase().includes(term)),
    );
    q("interviewTimeline").innerHTML = rows.length
      ? rows
          .map(
            (x) =>
              `<div class="timeline-item"><div><strong>${workspace.programLink(x)}</strong><span>${esc(x.week_start)} • ${x.reports} reportes protegidos</span></div>${tag(`${x.verified || 0} verified`, "good")}</div>`,
          )
          .join("")
      : '<div class="empty-state">No hay actividad que supere el umbral de privacidad.</div>';
  }
  function renderMatches() {
    q("stateGrid").innerHTML = publicDB.matchStates.length
      ? publicDB.matchStates
          .sort((a, b) => b.matches - a.matches)
          .map(
            (x) =>
              `<div class="state-card"><strong>${x.matches}</strong><span>${esc(x.state)}</span></div>`,
          )
          .join("")
      : '<div class="empty-state">Aún no hay matches agregados.</div>';
    q("matchTable").innerHTML = table(
      [
        ["Programa", "program_name", (r) => workspace.programLink(r)],
        ["Estado", "state"],
        ["Matches", "matches"],
      ],
      publicDB.matchPrograms,
    );
  }
  // ---------------------------------------------------------------------
  // Applicant Explorer: comparable cohort
  // Returns how many applicants fall in the chosen range, one anonymous row
  // per comparable applicant (programs applied, interviews, match) and the
  // programs where that cohort interviewed. Details need >= 5 profiles.
  // ---------------------------------------------------------------------
  const COHORT_MIN = 5;
  // Match Day is in mid/late March of the Match year (same rule as the DB).
  function matchCycleCompleted(cycle) {
    return new Date() >= new Date(Number(cycle), 2, 21);
  }
  function cohortArgs() {
    const cy = q("simCycle")?.value || "all";
    return {
      p_cycle: cy === "all" ? null : Number(cy),
      p_specialty: q("simSpecialty").value || null,
      p_step2: numOrNull(q("simStep2").value),
      p_usce: numOrNull(q("simUsce").value),
      p_lors: numOrNull(q("simLors").value),
      p_yog: numOrNull(q("simYog").value),
      p_visa_required:
        q("simVisa").value === "any" ? null : q("simVisa").value === "yes",
      p_step2_range: Number(q("simStep2Range")?.value || 10),
      p_yog_range: 5,
      p_lors_range: 1,
      p_usce_range: 3,
    };
  }
  function medianOf(arr) {
    return median(arr.filter((v) => v !== null && v !== undefined));
  }
  // Same rules as the SQL function, for demo mode.
  function demoCohort(a) {
    const spec = String(a.p_specialty || "").toLowerCase();
    const pool = demo.cycles
      .filter(
        (c) =>
          c.consentPublic &&
          (a.p_cycle === null || c.cycle === a.p_cycle) &&
          (!spec || String(c.specialty).toLowerCase() === spec) &&
          (a.p_step2 === null || (c.step2 !== null && c.step2 !== undefined && c.step2 !== "")),
      )
      .map((c) => {
        const d = (x, y) => (x === null || x === undefined || y === null || y === undefined ? 0 : Math.abs(x - y));
        const dist =
          d(c.step2, a.p_step2) / 5 + d(c.usce, a.p_usce) / 2 + d(c.lors, a.p_lors) * 1.5 + d(c.yog, a.p_yog) / 3 +
          (a.p_visa_required !== null && !!c.visa !== a.p_visa_required ? 4 : 0);
        const within = (v, t, r) => t === null || v === null || v === undefined || Math.abs(v - t) <= r;
        const inRange =
          (a.p_step2 === null || Math.abs(c.step2 - a.p_step2) <= a.p_step2_range) &&
          within(c.yog, a.p_yog, a.p_yog_range) &&
          within(c.lors, a.p_lors, a.p_lors_range) &&
          within(c.usce, a.p_usce, a.p_usce_range) &&
          (a.p_visa_required === null || !!c.visa === a.p_visa_required);
        return { c, dist, inRange };
      })
      .sort((x, y) => x.dist - y.dist);
    const inRange = pool.filter((p) => p.inRange).length;
    const widened = inRange < COHORT_MIN;
    const chosen = (widened ? pool.slice(0, 10) : pool.filter((p) => p.inRange).slice(0, 50)).map((p) => p.c);
    if (chosen.length < COHORT_MIN)
      return { in_range: inRange, cohort_size: chosen.length, widened, protected: true, min_size: COHORT_MIN, members: [], programs: [] };
    const members = chosen.map((c, i) => {
      const rs = demo.reports.filter((r) => r.applicantCycleId === c.id);
      const m = rs.find((r) => r.matched);
      return {
        label: "Perfil " + (i + 1),
        cycle: c.cycle,
        status: m ? "matched" : matchCycleCompleted(c.cycle) ? "no_match" : "in_progress",
        specialty: c.specialty,
        step2: c.step2,
        yog: c.yog,
        us_lors: c.lors,
        usce: c.usce,
        visa_required: !!c.visa,
        programs_applied: Math.max(c.programsApplied || 0, rs.filter((r) => r.applied).length) || null,
        interviews: Math.max(c.interviewInvites || 0, rs.filter((r) => r.interview).length),
        matched: !!m,
        match_program: m?.program || null,
        match_state: m?.state || null,
        interview_programs: rs
          .filter((r) => r.interview)
          .sort((x, y) => y.matched - x.matched || String(x.program).localeCompare(y.program))
          .map((r) => ({ program: r.program, state: r.state, specialty: r.specialty, signal: r.signal, matched: !!r.matched })),
        applied_programs: [...new Set(rs.filter((r) => r.applied && !r.interview).map((r) => r.program))],
      };
    });
    const by = {};
    chosen.forEach((c) =>
      demo.reports
        .filter((r) => r.applicantCycleId === c.id)
        .forEach((r) => {
          const k = r.program + "|" + r.specialty;
          by[k] ??= { program: r.program, state: r.state, specialty: r.specialty, applied: new Set(), interviews: new Set(), matches: 0 };
          if (r.applied) by[k].applied.add(c.id);
          if (r.interview) by[k].interviews.add(c.id);
          if (r.matched) by[k].matches++;
        }),
    );
    const programs = Object.values(by)
      .map((x) => ({ ...x, applied: x.applied.size, interviews: x.interviews.size }))
      .sort((x, y) => y.interviews - x.interviews || y.matches - x.matches || x.program.localeCompare(y.program));
    return {
      in_range: inRange,
      cohort_size: chosen.length,
      widened,
      protected: false,
      min_size: COHORT_MIN,
      ranges: { step2: a.p_step2_range, yog: a.p_yog_range, lors: a.p_lors_range, usce: a.p_usce_range },
      median_step2: medianOf(chosen.map((c) => c.step2)),
      median_lors: medianOf(chosen.map((c) => c.lors)),
      median_usce: medianOf(chosen.map((c) => c.usce)),
      median_interviews: medianOf(members.map((m) => m.interviews)),
      median_applied: medianOf(members.map((m) => m.programs_applied)),
      matched: members.filter((m) => m.matched).length,
      completed: members.filter((m) => m.status !== "in_progress").length,
      in_progress: members.filter((m) => m.status === "in_progress").length,
      by_cycle: members.reduce((o, m) => ((o[m.cycle] = (o[m.cycle] || 0) + 1), o), {}),
      members,
      programs,
    };
  }
  let lastCohort = null;
  async function findSimilar() {
    const a = cohortArgs();
    q("similarSummary").innerHTML = '<div class="empty-state">Buscando perfiles comparables…</div>';
    let res = null;
    if (cloudReady()) {
      try {
        res = await rpc("similar_cohort", a, false);
      } catch (e) {
        toast(
          /similar_cohort|Falta una función/i.test(e.message)
            ? "Falta la función similar_cohort. Ejecuta supabase/migrations/008_similar_cohort.sql en Supabase."
            : e.message,
          "bad",
        );
      }
    } else res = demoCohort(a);
    if (Array.isArray(res)) res = res[0] || null;
    if (res && !Array.isArray(res.members)) res.members = [];
    lastCohort = res;
    renderCohort(res, a);
  }
  const fmt = (v, suffix = "") =>
    v === null || v === undefined || v === "" ? "—" : `${Number.isInteger(Number(v)) ? v : Number(v).toFixed(1)}${suffix}`;
  function renderCohort(res, a) {
    const box = q("similarSummary"),
      mem = q("similarMembers"),
      prog = q("similarPrograms");
    box.className = "";
    if (!res) {
      box.innerHTML = '<div class="empty-state">No se pudo calcular la cohorte.</div>';
      mem.innerHTML = prog.innerHTML = "";
      return;
    }
    const rangeTxt = [
      a.p_step2 !== null ? `Step 2 ${a.p_step2} ± ${a.p_step2_range}` : null,
      a.p_yog !== null ? `YOG ± ${a.p_yog_range}` : null,
      a.p_lors !== null ? `LoRs ± ${a.p_lors_range}` : null,
      a.p_usce !== null ? `USCE ± ${a.p_usce_range} meses` : null,
      a.p_visa_required !== null ? (a.p_visa_required ? "requiere visa" : "sin visa") : null,
      a.p_specialty,
      a.p_cycle ? `solo Match ${a.p_cycle}` : "todos los ciclos",
    ]
      .filter(Boolean)
      .join(" · ");
    if (res.protected) {
      box.innerHTML = `<div class="metric-row cohort-metrics"><div class="metric"><strong>${res.in_range}</strong><span>Aplicantes en tu rango</span></div></div><div class="notice"><strong>Datos protegidos</strong><p>Hay ${res.cohort_size} perfil(es) comparable(s) para <b>${esc(rangeTxt)}</b>. Para proteger la privacidad, los detalles se muestran cuando hay al menos ${res.min_size || COHORT_MIN}. Prueba con un rango de Step 2 más amplio, otro ciclo o “Todos”.</p></div>`;
      mem.innerHTML = `<div class="empty-state">Se necesitan al menos ${res.min_size || COHORT_MIN} perfiles para mostrar cohortes.</div>`;
      prog.innerHTML = '<div class="empty-state">Sin datos suficientes.</div>';
      return;
    }
    const n = res.cohort_size || 0;
    const done = res.completed ?? n;
    const pctMatch = done ? Math.round((res.matched / done) * 100) : 0;
    const cycleTxt = Object.entries(res.by_cycle || {})
      .sort((x, y) => x[0].localeCompare(y[0]))
      .map(([cy, k]) => `${k} del Match ${cy}${matchCycleCompleted(cy) ? "" : " (en curso)"}`)
      .join(" · ");
    box.innerHTML = `<div class="metric-row cohort-metrics">
        <div class="metric"><strong>${res.in_range}</strong><span>Aplicantes en tu rango</span></div>
        <div class="metric"><strong>${n}</strong><span>Cohorte comparable</span></div>
        <div class="metric"><strong>${done ? `${res.matched}/${done}` : "—"}</strong><span>Hicieron Match${done ? ` (${pctMatch}%)` : ""}</span></div>
        <div class="metric"><strong>${fmt(res.median_interviews)}</strong><span>Mediana de entrevistas</span></div>
        <div class="metric"><strong>${fmt(res.median_applied)}</strong><span>Mediana programas aplicados</span></div>
        <div class="metric"><strong>${fmt(res.median_step2)}</strong><span>Mediana Step 2</span></div>
      </div>
      <p class="cohort-note">${cycleTxt ? `Cohorte: <b>${esc(cycleTxt)}</b>. ` : ""}${
        res.in_progress ? `El % de Match se calcula solo con ciclos terminados; los aplicantes en curso aparecen como «En curso». ` : ""
      }Rango: <b>${esc(rangeTxt)}</b>.${
        res.widened
          ? ` Solo ${res.in_range} aplicante(s) caen exactamente en ese rango, así que se muestran los <b>${n} perfiles más cercanos</b>.`
          : ""
      } Son patrones observados en la comunidad, no probabilidades de Match.</p>`;
    mem.innerHTML = `<table class="data-table cohort-table"><thead><tr><th>Perfil</th><th>Ciclo</th><th>Step 2</th><th>YOG</th><th>US LoRs</th><th>USCE</th><th>Visa</th><th>Programas aplicados</th><th>Entrevistas</th><th>Match</th><th></th></tr></thead><tbody>${res.members
      .map(
        (m, i) => `<tr>
          <td><b>${esc(m.label)}</b><br><span class="muted">${esc(m.specialty || "")}</span></td>
          <td>${fmt(m.cycle)}</td>
          <td>${fmt(m.step2)}</td><td>${fmt(m.yog)}</td><td>${fmt(m.us_lors)}</td><td>${fmt(m.usce)}</td>
          <td>${m.visa_required ? tag("Requiere", "warn") : tag("No")}</td>
          <td>${fmt(m.programs_applied)}</td>
          <td><b>${fmt(m.interviews)}</b></td>
          <td>${m.matched ? `${tag("Match", "good")}<br><span class="muted">${workspace.programLink({program:m.match_program,state:m.match_state,specialty:m.specialty})}${m.match_state ? " · " + esc(m.match_state) : ""}</span>` : m.status === "in_progress" ? tag("En curso", "warn") : tag("No match")}</td>
          <td><button class="text-btn small-link" data-cohort-toggle="${i}">${m.interview_programs.length ? "Ver programas" : ""}</button></td>
        </tr>
        <tr class="cohort-detail" id="cohortDetail${i}" hidden><td colspan="11">
          <div class="cohort-programs">${m.interview_programs
            .map(
              (p) =>
                `<span class="chip ${p.matched ? "matched" : ""}">${workspace.programLink(p)}${p.state ? ` <small>${esc(p.state)}</small>` : ""}${p.specialty && p.specialty !== m.specialty ? ` <small>${esc(p.specialty)}</small>` : ""}${p.signal && p.signal !== "None" ? ` <small class="sig">${esc(p.signal)}</small>` : ""}${p.matched ? " ★" : ""}</span>`,
            )
            .join("")}${
            (m.applied_programs || []).length
              ? `<div class="muted" style="margin-top:8px">Aplicó sin entrevista: ${m.applied_programs.map(esc).join(", ")}</div>`
              : ""
          }</div></td></tr>`,
      )
      .join("")}</tbody></table>`;
    const allProgs = res.programs || [];
    const showAll = prog.dataset.showAll === "1";
    prog.innerHTML = table(
      [
        ["Programa", "program", (r) => workspace.programLink(r)],
        ["Estado", "state"],
        ["Especialidad", "specialty"],
        ["Perfiles de la cohorte con entrevista", "interviews", (r) => `${r.interviews} de ${n}`],
        ["Matches", "matches", (r) => (r.matches ? tag(String(r.matches), "good") : "0")],
      ],
      showAll ? allProgs : allProgs.slice(0, 20),
    ) +
      (allProgs.length > 20
        ? `<button class="btn ghost small" style="margin-top:12px" data-cohort-progs>${showAll ? "Ver solo los 20 principales" : `Ver los ${allProgs.length} programas`}</button>`
        : "");
  }
  // Views are addressed as #/name (plain #name would make the browser jump
  // to the section element with that id).
  function hashView() {
    return location.hash.replace(/^#\/?/, "").split(/[/?]/)[0];
  }
  function isAdmin() {
    return profile?.role === "admin" || profile?.role === "moderator";
  }
  function renderNavRoles() {
    const b = document.querySelector('.nav-btn[data-view="admin"]');
    if (b) b.style.display = isAdmin() ? "" : "none";
    if (currentView === "admin" && !isAdmin() && !session) {
      currentView = "dashboard";
      updateNav(true);
    }
  }
  function fillMyForms() {
    const sel = q("applicationApplicant");
    const prev = sel.value;
    sel.innerHTML = myDB.cycles.length
      ? '<option value="">Selecciona tu ciclo</option>' +
        myDB.cycles
          .map(
            (c) =>
              `<option value="${esc(c.id)}">${esc(c.anonId)} • ${c.cycle} • ${esc(c.specialty)}</option>`,
          )
          .join("")
      : '<option value="">Primero guarda un perfil</option>';
    if (prev && myDB.cycles.some((c) => c.id === prev)) sel.value = prev;
    else if (myDB.cycles.length === 1) sel.value = myDB.cycles[0].id;
    return fillProgramOptions();
  }
  let programFillRun = 0;
  async function fillProgramOptions(selectId = null) {
    const run = ++programFillRun;
    const ps = q("applicationProgram");
    const keep = selectId ?? ps.value;
    const c = myDB.cycles.find((x) => x.id === q("applicationApplicant").value);
    if (!c) {
      publicDB.programs = cloudReady() ? [] : DEMO_PROGRAMS;
      ps.innerHTML =
        '<option value="">Primero selecciona tu applicant cycle</option>';
      return;
    }
    ps.innerHTML = '<option value="">Cargando programas…</option>';
    let list = [];
    try {
      list = await programsFor(c.specialty);
    } catch (e) {
      toast(e.message, "bad");
    }
    if (run !== programFillRun) return;
    publicDB.programs = list;
    ps.innerHTML =
      `<option value="">${list.length ? `Selecciona un programa (${list.length})` : "No hay programas en el catálogo — usa el campo manual"}</option>` +
      list
        .map(
          (p) =>
            `<option value="${esc(p.id)}" data-state="${esc(p.state || "")}" data-specialty="${esc(p.specialty || "")}">${esc(p.state || "—")} · ${esc(p.name)}${p.city ? " — " + esc(p.city) : ""}</option>`,
        )
        .join("");
    if (keep && list.some((p) => p.id === keep)) ps.value = keep;
    const f = q("applicationForm");
    if (!f.elements.id.value) f.elements.specialty.value = c.specialty;
  }
  function verificationTag(s) {
    return s === "verified"
      ? tag("Verified", "good")
      : s === "pending"
        ? tag("Pending", "warn")
        : s === "rejected"
          ? tag("Rejected", "bad")
          : tag("Unverified");
  }
  function renderMyData() {
    const need = cloudReady() && !session;
    const myBtn = q("useMyProfileBtn");
    if (myBtn) myBtn.style.display = myDB.cycles.length && (!cloudReady() || session) ? "" : "none";
    q("authRequired").style.display = need ? "flex" : "none";
    q("dataForms").style.display = need ? "none" : "grid";
    qa(".my-data-panel").forEach(
      (x) => (x.style.display = need ? "none" : "block"),
    );
    fillMyForms();
    q("myCycles").innerHTML = table(
      [
        ["Cycle", "cycle"],
        ["Anon ID", "anonId"],
        ["Specialty", "specialty"],
        ["YOG", "yog"],
        ["Step 2", "step2"],
        ["USCE", "usce"],
        ["LoRs", "lors"],
        [
          "Consent",
          "consentPublic",
          (r) => (r.consentPublic ? tag("Yes", "good") : tag("No", "warn")),
        ],
        [
          "",
          "",
          (r) =>
            `<div class="row-actions"><button data-edit-cycle="${esc(r.id)}">Editar</button><button data-delete-cycle="${esc(r.id)}">Eliminar</button></div>`,
        ],
      ],
      myDB.cycles,
    );
    q("myReports").innerHTML = table(
      [
        ["Program", "program", (r) => workspace.programLink(r)],
        ["Cycle", "cycle"],
        ["Signal", "signal"],
        [
          "Interview",
          "interview",
          (r) => (r.interview ? tag("Yes", "good") : tag("No")),
        ],
        [
          "Matched",
          "matched",
          (r) => (r.matched ? tag("Yes", "good") : tag("No")),
        ],
        [
          "Verification",
          "verificationStatus",
          (r) => verificationTag(r.verificationStatus),
        ],
        [
          "",
          "",
          (r) =>
            `<div class="row-actions"><button data-edit-report="${esc(r.id)}">Editar</button><button data-delete-report="${esc(r.id)}">Eliminar</button></div>`,
        ],
      ],
      myDB.reports,
    );
  }
  function renderAccount() {
    const logged = !!session;
    q("accountLoggedOut").style.display = logged ? "none" : "block";
    q("accountLoggedIn").style.display = logged ? "block" : "none";
    q("sessionEmail").textContent =
      session?.user?.email || profile?.email || "";
    q("sessionRole").textContent =
      { admin: "Administrador", moderator: "Moderador", user: "Usuario" }[
        profile?.role || "user"
      ] || profile?.role;
    q("accountTitle").textContent = logged ? "Mi cuenta" : "Registro / Login";
    const pw = q("passwordPanel");
    if (pw) {
      pw.style.display = logged ? "block" : "none";
      pw.classList.toggle("highlight", recoveryMode);
    }
  }
  async function renderAdmin() {
    const admin = isAdmin();
    q("adminDenied").style.display = admin ? "none" : "block";
    q("adminDenied").textContent = session
      ? "Esta sección requiere rol de administrador."
      : "Inicia sesión con una cuenta de administrador para ver esta sección.";
    q("adminArea").style.display = admin ? "block" : "none";
    if (!admin) return;
    q("adminSummary").innerHTML = '<div class="empty-state">Cargando…</div>';
    try {
      const settled = await Promise.allSettled([
        rpc("admin_site_summary", {}, false),
        request(
          "/rest/v1/profiles?select=id,email,display_name,role,created_at&order=created_at.desc&limit=300",
        ),
        request(
          "/rest/v1/applicant_cycles?select=id,user_id,source,anon_id,match_cycle,specialty,yog,step2_ck,created_at&order=created_at.desc&limit=1000",
        ),
        request(
          "/rest/v1/program_reports?select=id,user_id,source,program_name_snapshot,match_cycle,specialty,interview,ranked,matched,verification_status,created_at&order=created_at.desc&limit=2000",
        ),
      ]);
      const [summary, users, cycles, reports] = settled.map((x) =>
        x.status === "fulfilled" ? x.value : null,
      );
      // Tables are mandatory; the summary RPC is optional (counts fall back).
      const hardFail = settled.slice(1).find((x) => x.status === "rejected");
      if (hardFail) throw hardFail.reason;
      const s = summary || {};
      q("adminSummary").innerHTML =
        `<div class="metric-row admin-metrics"><div class="metric"><strong>${s.users ?? (users || []).length}</strong><span>Usuarios</span></div><div class="metric"><strong>${s.cycles ?? (cycles || []).length}</strong><span>Perfiles</span></div><div class="metric"><strong>${s.reports ?? (reports || []).length}</strong><span>Actividades</span></div><div class="metric"><strong>${s.pending_verifications ?? (reports || []).filter((r) => r.verification_status === "pending").length}</strong><span>Pendientes</span></div><div class="metric"><strong>${s.programs ?? "—"}</strong><span>Programas</span></div><div class="metric"><strong>${s.watch_subscriptions ?? "—"}</strong><span>Alertas</span></div></div>`;
      const byId = new Map((users || []).map((u) => [u.id, u]));
      const email = (id) => byId.get(id)?.email || id?.slice(0, 8) || "—";
      // Rows imported by an admin have no owner account.
      const owner = (r) =>
        r.user_id
          ? esc(email(r.user_id))
          : `<span class="tag warn">Importado</span> <span class="muted">${esc(String(r.source || "").replace(/^import:/, ""))}${r.anon_id ? " · " + esc(r.anon_id) : ""}</span>`;
      const batches = {};
      (cycles || []).forEach((c) => {
        if (!c.user_id && c.source && c.source !== "user") {
          batches[c.source] ??= { cycles: 0, reports: 0 };
          batches[c.source].cycles++;
        }
      });
      (reports || []).forEach((r) => {
        if (batches[r.source]) batches[r.source].reports++;
      });
      const batchHtml = Object.entries(batches)
        .map(
          ([src, v]) =>
            `<div class="backend-line"><span><b>Datos importados:</b> ${esc(src.replace(/^import:/, ""))} — ${v.cycles} perfiles, ${v.reports} invitaciones</span><button class="btn danger small" data-admin-delete-batch="${esc(src)}">Eliminar importación</button></div>`,
        )
        .join("");
      if (batchHtml)
        q("adminSummary").insertAdjacentHTML("beforeend", `<div class="backend-status" style="margin-top:12px">${batchHtml}</div>`);
      const me = session?.user?.id;
      const canDelete = profile?.role === "admin";
      const nCycles = (id) => (cycles || []).filter((c) => c.user_id === id).length;
      const nReports = (id) => (reports || []).filter((r) => r.user_id === id).length;
      adminUserIndex = new Map(
        (users || []).map((u) => [u.id, { email: u.email, cycles: nCycles(u.id), reports: nReports(u.id) }]),
      );
      q("adminUsers").innerHTML = table(
        [
          ["Email", "email"],
          ["Nombre", "display_name"],
          ["Perfiles", "", (r) => String(nCycles(r.id))],
          ["Reportes", "", (r) => String(nReports(r.id))],
          [
            "Rol",
            "role",
            (r) =>
              tag(r.role, r.role === "admin" ? "good" : r.role === "moderator" ? "warn" : ""),
          ],
          [
            "Creado",
            "created_at",
            (r) =>
              r.created_at ? new Date(r.created_at).toLocaleDateString() : "—",
          ],
          [
            "Acciones",
            "",
            (r) =>
              r.id === me
                ? '<span class="muted">Tu cuenta</span>'
                : `<div class="row-actions">${r.role !== "admin" ? `<button data-admin-role="admin" data-id="${esc(r.id)}">Hacer admin</button>` : ""}${r.role !== "moderator" ? `<button data-admin-role="moderator" data-id="${esc(r.id)}">Moderador</button>` : ""}${r.role !== "user" ? `<button data-admin-role="user" data-id="${esc(r.id)}">Usuario</button>` : ""}${canDelete ? `<button class="danger" data-admin-delete-user="${esc(r.id)}">Eliminar cuenta</button>` : ""}</div>`,
          ],
        ],
        users || [],
      );
      q("adminCycles").innerHTML = table(
        [
          ["Usuario", "user_id", owner],
          ["Cycle", "match_cycle"],
          ["Especialidad", "specialty"],
          ["YOG", "yog"],
          ["Step 2", "step2_ck"],
          [
            "",
            "",
            (r) =>
              `<button class="btn danger small" data-admin-delete-cycle="${esc(r.id)}">Eliminar</button>`,
          ],
        ],
        cycles || [],
      );
      q("adminReports").innerHTML = table(
        [
          ["Usuario", "user_id", owner],
          ["Programa", "program_name_snapshot", (r) => workspace.programLink(r)],
          ["Cycle", "match_cycle"],
          [
            "Interview",
            "interview",
            (r) => (r.interview ? tag("Yes", "good") : tag("No")),
          ],
          [
            "Matched",
            "matched",
            (r) => (r.matched ? tag("Yes", "good") : tag("No")),
          ],
          [
            "Verificación",
            "verification_status",
            (r) => verificationTag(r.verification_status),
          ],
          [
            "Acciones",
            "",
            (r) =>
              `<div class="row-actions"><button data-admin-verify="verified" data-id="${esc(r.id)}">Verificar</button><button data-admin-verify="rejected" data-id="${esc(r.id)}">Rechazar</button><button class="danger" data-admin-delete-report="${esc(r.id)}">Eliminar</button></div>`,
          ],
        ],
        reports || [],
      );
    } catch (e) {
      q("adminSummary").innerHTML =
        `<div class="empty-state">${esc(e.message)}</div>`;
    }
  }
  function updateNav(skipLoad = false) {
    const titles = {
      program: ["Program Profile", "Directorio y datos comunitarios protegidos."],
      compare: ["Program Compare", "Compara datos documentados de 2 a 5 programas."],
      dashboard: ["Dashboard", "Datos comunitarios protegidos y persistentes."],
      programs: ["Program Explorer", "Actividad agregada por programa."],
      intelligence: [
        "Program Intelligence",
        "Catálogo oficial y alertas de nuevos programas.",
      ],
      applicants: [
        "Applicant Explorer",
        "Compara tu perfil con cohortes anonimizadas.",
      ],
      interviews: [
        "Interview Tracker",
        "Actividad protegida por umbral de privacidad.",
      ],
      matches: ["Match Map", "Distribución comunitaria de matches."],
      data: ["Mis datos", "Tus perfiles y reportes persistentes."],
      account: ["Cuenta", "Autenticación y privacidad."],
      admin: ["Admin", "Moderación y verificación."],
    };
    qa(".nav-btn").forEach((x) =>
      x.classList.toggle("active", x.dataset.view === currentView),
    );
    qa(".view").forEach((v) =>
      v.classList.toggle("active-view", v.id === currentView),
    );
    if (!titles[currentView]) currentView = "dashboard";
    q("pageTitle").textContent = titles[currentView][0];
    q("pageSubtitle").textContent = titles[currentView][1];
    q("sidebar").classList.remove("open");
    document.body.classList.remove("nav-open");
    if (hashView() !== currentView && !/access_token|error/.test(location.hash))
      history.replaceState(null, "", "#/" + currentView);
    window.scrollTo({ top: 0, behavior: "instant" });
    if (skipLoad) return;
    if (currentView === "program" || currentView === "compare") workspace.loadView();
    if (currentView === "programs") workspace.renderPrograms();
    if (currentView === "applicants") findSimilar();
    if (currentView === "intelligence") loadIntelligence();
    if (currentView === "admin") { renderAdmin(); workspace.health(); }
  }
  function resetCycleForm() {
    q("cycleForm").reset();
    q("cycleForm").elements.id.value = "";
    q("cycleSaveBadge").textContent = "Nuevo";
  }
  function resetReportForm() {
    q("applicationForm").reset();
    q("applicationForm").elements.id.value = "";
    q("reportSaveBadge").textContent = "Nuevo";
    fillMyForms();
  }
  function setFormValues(form, obj, map) {
    Object.entries(map).forEach(([name, key]) => {
      const el = form.elements[name];
      if (!el) return;
      let v = obj[key];
      if (typeof v === "boolean") v = v ? "yes" : "no";
      if (v === null || v === undefined) v = "";
      el.value = String(v);
      // Selects silently become blank when the value has no matching option.
      if (el.tagName === "SELECT" && el.value !== String(v)) el.selectedIndex = 0;
    });
  }
  function syncInterviewFieldsSafe() {
    const f = q("applicationForm");
    const on = f.elements.interview.value === "yes";
    ["interviewDate", "interviewAttended", "ranked", "matched"].forEach(
      (n) => (f.elements[n].disabled = !on),
    );
  }
  function uid() {
    return crypto.randomUUID
      ? crypto.randomUUID()
      : "id-" + Date.now().toString(36) + Math.random().toString(36).slice(2);
  }
  async function saveCycle(e) {
    e.preventDefault();
    if (cloudReady() && !session) return toast("Inicia sesión primero.", "bad");
    const f = Object.fromEntries(new FormData(e.target));
    const local = {
      id: f.id || uid(),
      anonId: String(f.anonId || "").trim(),
      cycle: Number(f.cycle),
      specialty: String(f.specialty || "").trim(),
      yog: Number(f.yog),
      step1: f.step1,
      step1Attempts: Number(f.step1Attempts || 0),
      step2: f.step2 ? Number(f.step2) : null,
      step3: f.step3 ? Number(f.step3) : null,
      ecfmg: f.ecfmg === "yes",
      usce: Number(f.usce || 0),
      usceType: f.usceType,
      lors: Number(f.lors || 0),
      usPhysicianLors: Number(f.usPhysicianLors || 0),
      pdChairLor: f.pdChairLor === "yes",
      pubs: Number(f.pubs || 0),
      research: Number(f.research || 0),
      volunteer: f.volunteer === "yes",
      visa: f.visa === "yes",
      immigrationStatus: f.immigrationStatus,
      previousResidency: f.previousResidency === "yes",
      geoPreference: f.geoPreference,
      consentPublic: f.consentPublic === "yes",
      programsApplied: numOrNull(f.programsApplied),
      interviewInvites: numOrNull(f.interviewInvites),
      notes: f.notes,
    };
    if (!local.anonId || !local.specialty || !local.yog || !local.cycle)
      return toast("Completa ID anónimo, ciclo, especialidad y YOG.", "bad");
    try {
      if (cloudReady()) {
        const row = {
          user_id: session.user.id,
          anon_id: local.anonId,
          match_cycle: local.cycle,
          specialty: local.specialty,
          yog: local.yog,
          step1_status: local.step1,
          step1_attempts: local.step1Attempts,
          step2_ck: local.step2,
          step3: local.step3,
          ecfmg_status: local.ecfmg,
          usce_months: local.usce,
          usce_type: local.usceType || null,
          us_lors: local.lors,
          us_physician_lors: local.usPhysicianLors,
          pd_chair_lor: local.pdChairLor,
          publications: local.pubs,
          research_projects: local.research,
          volunteer_experience: local.volunteer,
          visa_required: local.visa,
          immigration_status: local.immigrationStatus || null,
          previous_residency_outside_us: local.previousResidency,
          geographic_preference: local.geoPreference || null,
          consent_public: local.consentPublic,
          programs_applied: local.programsApplied,
          interview_invites: local.interviewInvites,
          notes: local.notes || null,
        };
        if (f.id) {
          const upd = await request(
            `/rest/v1/applicant_cycles?id=eq.${encodeURIComponent(f.id)}&user_id=eq.${encodeURIComponent(session.user.id)}`,
            { method: "PATCH", body: row, prefer: "return=representation" },
          );
          if (!upd?.length)
            throw new Error("No se pudo actualizar: el perfil ya no existe o no te pertenece.");
        } else
          await request(
            "/rest/v1/applicant_cycles?on_conflict=user_id,match_cycle,specialty",
            {
              method: "POST",
              body: row,
              prefer: "resolution=merge-duplicates,return=minimal",
            },
          );
      } else {
        // Same uniqueness rule as the database: one profile per cycle+specialty.
        let ix = demo.cycles.findIndex((x) => x.id === local.id);
        if (ix < 0)
          ix = demo.cycles.findIndex(
            (x) =>
              x.cycle === local.cycle &&
              String(x.specialty).toLowerCase() === local.specialty.toLowerCase(),
          );
        if (ix >= 0) {
          local.id = demo.cycles[ix].id;
          demo.cycles[ix] = local;
        } else demo.cycles.push(local);
        demo.reports.forEach((r) => {
          if (r.applicantCycleId === local.id) {
            r.cycle = local.cycle;
            r.specialty = local.specialty;
          }
        });
        writeJSON(DEMO_KEY, demo);
      }
      toast(f.id ? "Perfil actualizado." : "Perfil guardado correctamente.");
      resetCycleForm();
      await refresh();
    } catch (err) {
      toast(err.message, "bad");
    }
  }
  async function saveReport(e) {
    e.preventDefault();
    if (cloudReady() && !session) return toast("Inicia sesión primero.", "bad");
    const f = Object.fromEntries(new FormData(e.target)),
      c = myDB.cycles.find((x) => x.id === f.applicantCycleId);
    if (!c) return toast("Selecciona un applicant cycle.", "bad");
    const p = publicDB.programs.find((x) => x.id === f.programId),
      program = (p?.name || f.programManual || "").trim(),
      state = (p?.state || f.state || "").toUpperCase(),
      // The database forces the report specialty to match the applicant cycle.
      specialty = p?.specialty || c.specialty || f.specialty;
    if (!program) return toast("Selecciona o escribe un programa.", "bad");
    if (state && !/^[A-Z]{2}$/.test(state))
      return toast("El estado debe ser el código de 2 letras (ej. FL).", "bad");
    const local = {
      id: f.id || uid(),
      applicantCycleId: c.id,
      cycle: c.cycle,
      programId: p?.id || null,
      program,
      state,
      specialty,
      applied: f.applied === "yes",
      signal: f.signal,
      geoPreferenceUsed: f.geoPreferenceUsed === "yes",
      interview: f.interview === "yes",
      // FIX: the DB rejects an interview date when interview = No
      // (check constraint) — that produced an opaque error on save.
      interviewDate: f.interview === "yes" ? f.interviewDate || null : null,
      interviewAttended:
        f.interview === "yes" && f.interviewAttended === "yes",
      ranked: f.ranked === "yes",
      matched: f.matched === "yes",
      track: f.track,
      retrospective: f.retrospective === "yes",
      verificationRequested: f.verificationRequested === "yes",
      verificationStatus:
        f.verificationRequested === "yes" ? "pending" : "unverified",
      verificationNote: f.verificationNote || null,
    };
    if (local.matched && !local.interview)
      return toast(
        "Un Match debe estar asociado a una entrevista reportada.",
        "bad",
      );
    if (local.ranked && !local.interview)
      return toast(
        "Un programa rankeado debe tener entrevista reportada.",
        "bad",
      );
    try {
      if (cloudReady()) {
        const row = {
          applicant_cycle_id: c.id,
          program_id: p?.id || null,
          program_name_snapshot: program,
          state_snapshot: state,
          specialty,
          applied: local.applied,
          signal: local.signal,
          geo_preference_used: local.geoPreferenceUsed,
          interview: local.interview,
          interview_date: local.interviewDate,
          interview_attended: local.interviewAttended,
          ranked: local.ranked,
          matched: local.matched,
          track: local.track,
          retrospective: local.retrospective,
          verification_requested: local.verificationRequested,
          verification_note: local.verificationNote,
        };
        if (f.id) {
          const upd = await request(
            `/rest/v1/program_reports?id=eq.${encodeURIComponent(f.id)}&user_id=eq.${encodeURIComponent(session.user.id)}`,
            { method: "PATCH", body: row, prefer: "return=representation" },
          );
          if (!upd?.length)
            throw new Error("No se pudo actualizar: el reporte ya no existe o no te pertenece.");
        } else
          await request("/rest/v1/program_reports", {
            method: "POST",
            body: row,
            prefer: "return=minimal",
          });
      } else {
        const ix = demo.reports.findIndex((x) => x.id === local.id);
        if (ix >= 0) demo.reports[ix] = local;
        else demo.reports.push(local);
        writeJSON(DEMO_KEY, demo);
      }
      toast(f.id ? "Reporte actualizado." : "Reporte guardado correctamente.");
      resetReportForm();
      await refresh();
    } catch (err) {
      toast(err.message, "bad");
    }
  }
  function editCycle(id) {
    const c = myDB.cycles.find((x) => x.id === id);
    if (!c) return;
    setFormValues(q("cycleForm"), c, {
      id: "id",
      anonId: "anonId",
      cycle: "cycle",
      specialty: "specialty",
      yog: "yog",
      step1: "step1",
      step1Attempts: "step1Attempts",
      step2: "step2",
      step3: "step3",
      ecfmg: "ecfmg",
      usce: "usce",
      usceType: "usceType",
      lors: "lors",
      usPhysicianLors: "usPhysicianLors",
      pdChairLor: "pdChairLor",
      pubs: "pubs",
      research: "research",
      volunteer: "volunteer",
      visa: "visa",
      immigrationStatus: "immigrationStatus",
      previousResidency: "previousResidency",
      geoPreference: "geoPreference",
      consentPublic: "consentPublic",
      programsApplied: "programsApplied",
      interviewInvites: "interviewInvites",
      notes: "notes",
    });
    q("cycleSaveBadge").textContent = "Editando";
    q("cycleForm").closest(".panel").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  async function editReport(id) {
    const r = myDB.reports.find((x) => x.id === id);
    if (!r) return;
    const form = q("applicationForm");
    form.reset();
    form.elements.applicantCycleId.value = r.applicantCycleId;
    // FIX: wait for the program list of this cycle before selecting the
    // program, otherwise the dropdown showed "Selecciona un programa" and a
    // save would turn the report into a manual entry.
    await fillProgramOptions(r.programId || "");
    setFormValues(form, r, {
      id: "id",
      applicantCycleId: "applicantCycleId",
      state: "state",
      specialty: "specialty",
      applied: "applied",
      signal: "signal",
      geoPreferenceUsed: "geoPreferenceUsed",
      interview: "interview",
      interviewDate: "interviewDate",
      interviewAttended: "interviewAttended",
      ranked: "ranked",
      matched: "matched",
      track: "track",
      retrospective: "retrospective",
      verificationRequested: "verificationRequested",
      verificationNote: "verificationNote",
    });
    const inList = r.programId && form.elements.programId.value === r.programId;
    form.elements.programManual.value = inList ? "" : r.program || "";
    syncInterviewFieldsSafe();
    q("reportSaveBadge").textContent = "Editando";
    form.closest(".panel").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  async function deleteCycle(id) {
    if (!confirm("¿Eliminar este perfil de ciclo y sus reportes asociados?"))
      return;
    try {
      if (cloudReady())
        await request(
          `/rest/v1/applicant_cycles?id=eq.${encodeURIComponent(id)}`,
          { method: "DELETE", prefer: "return=minimal" },
        );
      else {
        demo.cycles = demo.cycles.filter((x) => x.id !== id);
        demo.reports = demo.reports.filter((x) => x.applicantCycleId !== id);
        writeJSON(DEMO_KEY, demo);
      }
      if (q("cycleForm").elements.id.value === id) resetCycleForm();
      if (myDB.reports.some((r) => r.applicantCycleId === id && r.id === q("applicationForm").elements.id.value))
        resetReportForm();
      toast("Perfil eliminado.");
      await refresh();
    } catch (e) {
      toast(e.message, "bad");
    }
  }
  async function deleteReport(id) {
    if (!confirm("¿Eliminar este reporte?")) return;
    try {
      if (cloudReady())
        await request(
          `/rest/v1/program_reports?id=eq.${encodeURIComponent(id)}`,
          { method: "DELETE", prefer: "return=minimal" },
        );
      else {
        demo.reports = demo.reports.filter((x) => x.id !== id);
        writeJSON(DEMO_KEY, demo);
      }
      if (q("applicationForm").elements.id.value === id) resetReportForm();
      toast("Reporte eliminado.");
      await refresh();
    } catch (e) {
      toast(e.message, "bad");
    }
  }
  function download(name, text, type = "application/json") {
    const a = document.createElement("a"),
      u = URL.createObjectURL(new Blob([text], { type }));
    a.href = u;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(u), 500);
  }
  function csv(rows) {
    if (!rows.length) return "";
    const keys = [...new Set(rows.flatMap((r) => Object.keys(r)))];
    return [
      keys.join(","),
      ...rows.map((r) =>
        keys
          .map((k) => `"${String(r[k] ?? "").replaceAll('"', '""')}"`)
          .join(","),
      ),
    ].join("\n");
  }

  async function loadIntelSpecialties() {
    if (!cloudReady()) {
      intelDB.specialties = [];
      q("syncProgress").textContent = "Modo demo — sin catálogo oficial";
    } else {
      try {
        intelDB.specialties =
          (await request(
            "/rest/v1/acgme_specialties?select=acgme_specialty_id,name,baseline_complete,last_synced_at,last_program_count&active=eq.true&order=name.asc",
            { publicOnly: true },
          )) || [];
        const done = intelDB.specialties.filter((x) => x.baseline_complete).length;
        q("syncProgress").textContent = intelDB.specialties.length
          ? `${done}/${intelDB.specialties.length} especialidades sincronizadas`
          : "Catálogo aún no sincronizado";
      } catch (e) {
        intelDB.specialties = [];
        q("syncProgress").textContent = "Catálogo no disponible";
      }
    }
    // Fall back to the specialties already known by the app.
    const names = intelDB.specialties.length
      ? intelDB.specialties.map((x) => x.name)
      : specialties();
    const opts = names
      .map((x) => `<option value="${esc(x)}">${esc(x)}</option>`)
      .join("");
    setOptions(
      "officialSpecialty",
      '<option value="all">Todas las especialidades</option>' + opts,
      "all",
    );
    setOptions("watchSpecialty", opts, names.includes("Internal Medicine") ? "Internal Medicine" : undefined);
  }
  function safeUrl(u) {
    return /^https?:\/\//i.test(String(u || "")) ? String(u) : "#";
  }
  async function loadOfficialPrograms() {
    if (!cloudReady()) {
      q("officialProgramsTable").innerHTML =
        '<div class="empty-state">Conecta Supabase para consultar el catálogo oficial.</div>';
      return;
    }
    const term = (q("officialSearch").value || "")
        .trim()
        .replace(/[*,()]/g, " "),
      spec = q("officialSpecialty").value;
    let path =
      "/rest/v1/programs?select=id,acgme_program_id,name,specialty,city,state&active=eq.true&order=name.asc&limit=100";
    if (spec && spec !== "all")
      path += "&specialty=eq." + encodeURIComponent(spec);
    if (term) path += "&name=ilike." + encodeURIComponent("*" + term + "*");
    q("officialProgramsTable").innerHTML = '<div class="empty-state">Buscando…</div>';
    intelDB.official = (await request(path, { publicOnly: true })) || [];
    intelDB.sources = new Map();
    if (intelDB.official.length) {
      const ids = intelDB.official
        .map((x) => x.acgme_program_id)
        .filter(Boolean);
      const src =
        (await request(
          "/rest/v1/program_external_sources?select=acgme_program_id,source,source_url,data_scope&acgme_program_id=in.(" +
            ids.map((x) => `"${String(x).replace(/"/g, "")}"`).join(",") +
            ")",
          { publicOnly: true },
        )) || [];
      src.forEach((x) => {
        if (!intelDB.sources.has(x.acgme_program_id))
          intelDB.sources.set(x.acgme_program_id, {});
        intelDB.sources.get(x.acgme_program_id)[x.source] = x;
      });
    }
    renderOfficialPrograms();
  }
  function extLink(code, source, label) {
    const x = intelDB.sources.get(code)?.[source];
    return x
      ? `<a class="source-link" href="${esc(safeUrl(x.source_url))}" target="_blank" rel="noopener noreferrer">${esc(label)} ↗</a>`
      : '<span class="muted">—</span>';
  }
  function renderOfficialPrograms() {
    const cols = [
      ["Programa", "name", (r) => workspace.programLink(r)],
      ["Especialidad", "specialty"],
      [
        "Ciudad/Estado",
        "place",
        (r) => esc([r.city, r.state].filter(Boolean).join(", ") || "—"),
      ],
      ["ACGME ID", "acgme_program_id"],
      [
        "Fuentes",
        "src",
        (r) =>
          `<div class="source-links">${extLink(r.acgme_program_id, "acgme", "ACGME")}${extLink(r.acgme_program_id, "freida", "FREIDA")}${extLink(r.acgme_program_id, "residency_explorer", "Residency Explorer")}</div>`,
      ],
    ];
    q("officialProgramsTable").innerHTML = table(cols, intelDB.official);
  }
  async function loadNewAccredited() {
    if (!cloudReady()) {
      q("newPrograms").innerHTML =
        '<div class="empty-state">Disponible cuando Supabase está conectado.</div>';
      return;
    }
    try {
      const rows =
        (await rpc(
          "new_accredited_programs",
          {
            p_specialty: null,
            p_state: null,
            p_since: new Date(Date.now() - 90 * 86400000).toISOString(),
          },
          true,
        )) || [];
      q("newPrograms").innerHTML = rows.length
        ? rows
            .slice(0, 25)
            .map(
              (x) =>
                `<div class="intel-item unread"><div><strong>${workspace.programLink(x)}</strong><small>${esc(x.specialty)} · ${esc([x.city, x.state].filter(Boolean).join(", "))}<br>${esc(x.accreditation_status || "Newly detected")} · ${new Date(x.first_seen_at).toLocaleString()}</small></div><div class="intel-actions"><a class="btn ghost small" href="${esc(safeUrl(x.source_url))}" target="_blank" rel="noopener noreferrer">ACGME ↗</a></div></div>`,
            )
            .join("")
        : '<div class="empty-state">No hay nuevas incorporaciones detectadas desde el inicio del baseline.</div>';
    } catch (e) {
      q("newPrograms").innerHTML =
        `<div class="empty-state">${esc(e.message)}</div>`;
    }
  }
  async function loadWatches() {
    if (!session) {
      intelDB.watches = [];
      q("watchList").innerHTML = "";
      return;
    }
    intelDB.watches =
      (await request(
        "/rest/v1/program_watch_subscriptions?select=*&order=created_at.desc",
      )) || [];
    q("watchList").innerHTML = intelDB.watches.length
      ? intelDB.watches
          .map(
            (x) =>
              `<div class="intel-item"><div><strong>${esc(x.specialty)}</strong><small>${x.state ? "Estado: " + esc(x.state) : "Todos los estados"}</small></div><button class="btn danger small" data-watch-delete="${esc(x.id)}">Eliminar</button></div>`,
          )
          .join("")
      : '<div class="empty-state">No tienes alertas creadas.</div>';
  }
  async function loadNotifications() {
    if (!session) {
      intelDB.notifications = [];
      q("notifications").innerHTML =
        '<div class="empty-state">Inicia sesión para ver notificaciones.</div>';
      q("notifBadge").style.display = "none";
      return;
    }
    intelDB.notifications =
      (await request(
        "/rest/v1/notifications?select=*&order=created_at.desc&limit=50",
      )) || [];
    const unread = intelDB.notifications.filter((x) => !x.read_at);
    // FIX: "Alertas del navegador" asked for permission but never showed a
    // notification. New unread items now raise a browser notification.
    if (seenNotifications && "Notification" in window && Notification.permission === "granted")
      unread
        .filter((x) => !seenNotifications.has(x.id))
        .slice(0, 3)
        .forEach((x) => {
          try {
            new Notification(x.title, { body: x.body, icon: "app-icon.svg" });
          } catch {}
        });
    seenNotifications = new Set(intelDB.notifications.map((x) => x.id));
    q("notifBadge").textContent = unread.length;
    q("notifBadge").style.display = unread.length ? "inline-grid" : "none";
    q("notifications").innerHTML = intelDB.notifications.length
      ? intelDB.notifications
          .map(
            (x) =>
              `<div class="intel-item ${x.read_at ? "" : "unread"}"><div><strong>${esc(x.title)}</strong><small>${esc(x.body)}<br>${new Date(x.created_at).toLocaleString()}</small></div><div class="intel-actions">${x.source_url ? `<a class="btn ghost small" href="${esc(safeUrl(x.source_url))}" target="_blank" rel="noopener noreferrer">Fuente ↗</a>` : ""}${x.read_at ? "" : `<button class="btn ghost small" data-notification-read="${esc(x.id)}">Marcar leída</button>`}</div></div>`,
          )
          .join("")
      : '<div class="empty-state">Aún no tienes notificaciones.</div>';
  }
  async function loadIntelligence() {
    if (!q("officialProgramsTable")) return;
    try {
      await loadIntelSpecialties();
      const res = await Promise.allSettled([
        loadOfficialPrograms(),
        loadNewAccredited(),
        loadWatches(),
        loadNotifications(),
      ]);
      const bad = res.find((x) => x.status === "rejected");
      if (bad) throw bad.reason;
    } catch (e) {
      if (q("officialProgramsTable").textContent.includes("Buscando"))
        q("officialProgramsTable").innerHTML = `<div class="empty-state">${esc(e.message)}</div>`;
      toast(e.message, "bad");
    }
    q("watchLoggedOut").style.display = session ? "none" : "block";
    q("watchArea").style.display = session ? "block" : "none";
  }

  const workspace = window.CMEWorkspace({ q, esc, rpc, cloudReady, getMyData: () => myDB, getUserId: () => session?.user?.id, toast, isAdmin });

  let refreshRun = 0;
  async function refresh() {
    const run = ++refreshRun;
    renderStatus();
    const res = await Promise.allSettled([
      loadPrograms(),
      loadProfile(),
      loadMyData(),
      loadPublic(),
      workspace.loadIdentityIndex(),
    ]);
    if (run !== refreshRun) return; // a newer refresh superseded this one
    const errs = [
      ...new Set(
        res.filter((x) => x.status === "rejected").map((x) => x.reason?.message),
      ),
    ].filter(Boolean);
    if (errs.length) toast(errs[0], "bad");
    renderStatus();
    renderNavRoles();
    fillSpecialties();
    renderDashboard();
    workspace.renderPersonal();
    renderPrograms();
    renderInterviews();
    renderMatches();
    renderMyData();
    renderAccount();
    if (currentView === "program" || currentView === "compare") workspace.loadView();
    if (currentView === "intelligence") loadIntelligence();
    if (currentView === "admin") { renderAdmin(); workspace.health(); }
  }
  q("nav").addEventListener("click", (e) => {
    const b = e.target.closest(".nav-btn");
    if (!b) return;
    currentView = b.dataset.view;
    updateNav();
  });
  document.body.addEventListener("click", (e) => {
    const go = e.target.closest("[data-go]");
    if (go) {
      currentView = go.dataset.go;
      updateNav();
    }
    const ec = e.target.closest("[data-edit-cycle]");
    if (ec) editCycle(ec.dataset.editCycle);
    const dc = e.target.closest("[data-delete-cycle]");
    if (dc) deleteCycle(dc.dataset.deleteCycle);
    const er = e.target.closest("[data-edit-report]");
    if (er) editReport(er.dataset.editReport);
    const dr = e.target.closest("[data-delete-report]");
    if (dr) deleteReport(dr.dataset.deleteReport);
  });
  q("menuBtn").addEventListener("click", () => {
    q("sidebar").classList.toggle("open");
    document.body.classList.toggle("nav-open", q("sidebar").classList.contains("open"));
  });
  q("navOverlay")?.addEventListener("click", () => {
    q("sidebar").classList.remove("open");
    document.body.classList.remove("nav-open");
  });
  window.addEventListener("hashchange", () => {
    const v = hashView();
    if (v && (v !== currentView || v === "program" || v === "compare") && q(v)?.classList.contains("view")) {
      currentView = v;
      updateNav();
    }
  });
  q("applicationApplicant").addEventListener("change", () => fillProgramOptions());
  const syncInterviewFields = () => {
    const f = q("applicationForm");
    const on = f.elements.interview.value === "yes";
    ["interviewDate", "interviewAttended", "ranked", "matched"].forEach((n) => {
      f.elements[n].disabled = !on;
      if (!on) f.elements[n].value = n === "interviewDate" ? "" : "no";
    });
  };
  q("applicationForm").elements.interview.addEventListener("change", syncInterviewFields);
  q("applicationForm").addEventListener("reset", () => setTimeout(syncInterviewFields, 0));
  syncInterviewFieldsSafe();
  q("globalCycle").addEventListener("change", refresh);
  ["programSearch", "programSpecialty", "programOutcome"].forEach((id) =>
    q(id).addEventListener("input", renderPrograms),
  );
  ["interviewSearch", "interviewSpecialty"].forEach((id) =>
    q(id).addEventListener("input", renderInterviews),
  );
  q("findSimilarBtn").addEventListener("click", findSimilar);
  q("useMyProfileBtn").addEventListener("click", () => {
    const c = [...myDB.cycles].sort((x, y) => (y.cycle || 0) - (x.cycle || 0))[0];
    if (!c) return;
    const set = (id, v) => (q(id).value = v === null || v === undefined ? "" : v);
    set("simStep2", c.step2);
    set("simYog", c.yog);
    set("simLors", c.lors);
    set("simUsce", c.usce || "");
    q("simVisa").value = c.visa ? "yes" : "no";
    if ([...q("simSpecialty").options].some((o) => o.value === c.specialty)) q("simSpecialty").value = c.specialty;
    q("simCycle").value = "all";
    findSimilar();
  });
  q("similarMembers").addEventListener("click", (e) => {
    const b = e.target.closest("[data-cohort-toggle]");
    if (!b) return;
    const row = q("cohortDetail" + b.dataset.cohortToggle);
    row.hidden = !row.hidden;
    b.textContent = row.hidden ? "Ver programas" : "Ocultar";
  });
  q("similarPrograms").addEventListener("click", (e) => {
    if (!e.target.closest("[data-cohort-progs]")) return;
    const el = q("similarPrograms");
    el.dataset.showAll = el.dataset.showAll === "1" ? "0" : "1";
    if (lastCohort) renderCohort(lastCohort, cohortArgs());
  });
  ["simSpecialty", "simVisa", "simStep2Range", "simCycle"].forEach((id) => q(id).addEventListener("change", findSimilar));
  ["simStep2", "simUsce", "simLors", "simYog"].forEach((id) =>
    q(id).addEventListener("keydown", (e) => e.key === "Enter" && findSimilar()),
  );
  q("cycleForm").addEventListener("submit", saveCycle);
  q("applicationForm").addEventListener("submit", saveReport);
  q("resetCycleForm").addEventListener("click", resetCycleForm);
  q("resetReportForm").addEventListener("click", resetReportForm);
  q("applicationProgram").addEventListener("change", (e) => {
    const o = e.target.selectedOptions[0];
    if (o?.dataset.state)
      q("applicationForm").elements.state.value = o.dataset.state;
    if (o?.dataset.specialty)
      q("applicationForm").elements.specialty.value = o.dataset.specialty;
  });
  q("authForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!cloudReady())
      return (q("authStatus").textContent =
        "Primero configura Supabase en cloud-config.js.");
    const f = Object.fromEntries(new FormData(e.target)),
      // FIX: e.submitter is missing in older Safari, which made "Crear cuenta"
      // attempt a login instead. The last clicked button is tracked instead.
      act = e.submitter?.dataset.action || lastAuthAction || "signin",
      email = String(f.email || "").trim().toLowerCase();
    lastAuthAction = null;
    const btns = qa("#authForm button");
    btns.forEach((b) => (b.disabled = true));
    setAuthStatus(act === "signup" ? "Creando cuenta…" : "Iniciando sesión…");
    try {
      const d =
        act === "signup"
          ? await signup(email, f.password)
          : await signin(email, f.password);
      if (d.access_token) {
        setAuthStatus("Sesión iniciada.", "good");
        toast("Bienvenido.");
        e.target.reset();
        await refresh();
      } else if (act === "signup" && Array.isArray(d.identities) && !d.identities.length) {
        setAuthStatus("Ya existe una cuenta con ese email. Inicia sesión o recupera tu contraseña.", "bad");
      } else
        setAuthStatus(
          "Cuenta creada. Te enviamos un correo de confirmación: abre el enlace y volverás aquí con la sesión iniciada.",
          "good",
        );
    } catch (err) {
      setAuthStatus(err.message, "bad");
    } finally {
      btns.forEach((b) => (b.disabled = false));
    }
  });
  let lastAuthAction = null;
  qa("#authForm button[data-action]").forEach((b) =>
    b.addEventListener("click", () => (lastAuthAction = b.dataset.action)),
  );
  function setAuthStatus(msg, type = "") {
    const el = q("authStatus");
    el.textContent = msg;
    el.className = "status-box " + type;
  }
  q("passwordForm")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    if (String(f.password || "").length < 8)
      return toast("La contraseña debe tener al menos 8 caracteres.", "bad");
    if (f.password !== f.password2)
      return toast("Las contraseñas no coinciden.", "bad");
    try {
      await updatePassword(f.password);
      recoveryMode = false;
      e.target.reset();
      renderAccount();
      toast("Contraseña actualizada.");
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("forgotPasswordBtn").addEventListener("click", async () => {
    if (!cloudReady()) return toast("Supabase no está configurado.", "bad");
    const email = (
      q("authForm").elements.email.value || prompt("Email de la cuenta:") || ""
    ).trim();
    if (!email) return;
    try {
      await sendRecovery(email);
      toast("Si la cuenta existe, recibirás un correo para restablecer la contraseña.");
    } catch (e) {
      toast(e.message, "bad");
    }
  });
  q("signOutBtn").addEventListener("click", async () => {
    await signout();
    toast("Sesión cerrada.");
    await refresh();
  });
  q("deleteAccountBtn").addEventListener("click", async () => {
    if (!session) return;
    if (
      !confirm(
        "Esto eliminará tus perfiles, reportes, alertas y notificaciones de la plataforma. Esta acción no se puede deshacer. ¿Continuar?",
      )
    )
      return;
    try {
      await request("/rest/v1/rpc/delete_my_data", {
        method: "POST",
        body: {},
      });
      await signout();
      toast("Tus datos fueron eliminados.");
      await refresh();
    } catch (e) {
      toast(e.message, "bad");
    }
  });
  q("exportJsonBtn").addEventListener("click", () =>
    download(
      "img-cuba-my-data.json",
      JSON.stringify({ cycles: myDB.cycles, reports: myDB.reports }, null, 2),
    ),
  );
  q("exportCsvBtn").addEventListener("click", () =>
    download("img-cuba-program-reports.csv", csv(myDB.reports), "text/csv"),
  );
  q("verificationQueue")?.addEventListener("click", async (e) => {
    const b = e.target.closest("[data-verify]");
    if (!b) return;
    try {
      await rpc(
        "admin_set_verification",
        { p_report_id: b.dataset.id, p_status: b.dataset.verify, p_note: null },
        false,
      );
      toast("Estado actualizado.");
      await refresh();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("adminRefresh")?.addEventListener("click", renderAdmin);
  q("adminSummary")?.addEventListener("click", async (e) => {
    const b = e.target.closest("[data-admin-delete-batch]");
    if (!b) return;
    const src = b.dataset.adminDeleteBatch;
    if (!confirm(`¿Eliminar todos los datos importados de «${src.replace(/^import:/, "")}» (perfiles e invitaciones)? Esta acción no se puede deshacer.`)) return;
    try {
      await request(
        "/rest/v1/applicant_cycles?user_id=is.null&source=eq." + encodeURIComponent(src),
        { method: "DELETE", prefer: "return=minimal" },
      );
      toast("Importación eliminada.");
      await refresh();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("adminReports")?.addEventListener("click", async (e) => {
    const v = e.target.closest("[data-admin-verify]"),
      d = e.target.closest("[data-admin-delete-report]");
    if (v) {
      try {
        await rpc(
          "admin_set_verification",
          {
            p_report_id: v.dataset.id,
            p_status: v.dataset.adminVerify,
            p_note: null,
          },
          false,
        );
        toast("Verificación actualizada.");
        await refresh();
      } catch (err) {
        toast(err.message, "bad");
      }
      return;
    }
    if (d) {
      if (!confirm("¿Eliminar esta actividad?")) return;
      try {
        await request(
          "/rest/v1/program_reports?id=eq." +
            encodeURIComponent(d.dataset.adminDeleteReport),
          { method: "DELETE", prefer: "return=minimal" },
        );
        toast("Actividad eliminada.");
        await refresh();
      } catch (err) {
        toast(err.message, "bad");
      }
    }
  });
  q("adminUsers")?.addEventListener("click", async (e) => {
    const del = e.target.closest("[data-admin-delete-user]");
    if (del) return adminDeleteUser(del.dataset.adminDeleteUser);
    const b = e.target.closest("[data-admin-role]");
    if (!b) return;
    const role = b.dataset.adminRole;
    const label = { admin: "administrador", moderator: "moderador", user: "usuario normal" }[role];
    if (!confirm(`¿Cambiar el rol de esta cuenta a ${label}?`)) return;
    try {
      await rpc("admin_set_user_role", { p_user_id: b.dataset.id, p_role: role }, false);
      toast("Rol actualizado.");
      await renderAdmin();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  // Deletes the whole account: login, profiles, reports, alerts and
  // notifications (server-side, see migrations/005_admin_delete_user.sql).
  async function adminDeleteUser(id) {
    const u = adminUserIndex.get(id) || {};
    const email = u.email || id;
    if (
      !confirm(
        `¿Eliminar la cuenta ${email} y todos sus datos (${u.cycles ?? 0} perfiles, ${u.reports ?? 0} reportes, alertas y notificaciones)? Esta acción no se puede deshacer.`,
      )
    )
      return;
    try {
      const r = await rpc("admin_delete_user", { p_user_id: id }, false);
      toast(
        `Cuenta eliminada (${r?.cycles ?? 0} perfiles, ${r?.reports ?? 0} reportes, ${r?.alerts ?? 0} alertas).`,
      );
      await refresh();
    } catch (err) {
      const m = String(err.message || "");
      toast(
        /admin_delete_user|PGRST202|could not find|Falta una función/i.test(m)
          ? "Falta la función admin_delete_user. Ejecuta supabase/migrations/005_admin_delete_user.sql en Supabase."
          : /own account/i.test(m)
            ? "No puedes eliminar tu propia cuenta desde el panel de administración."
            : /last administrator/i.test(m)
              ? "No se puede eliminar al último administrador."
              : /Admin required/i.test(m)
                ? "Solo un administrador puede eliminar cuentas."
                : m,
        "bad",
      );
    }
  }
  q("adminCycles")?.addEventListener("click", async (e) => {
    const d = e.target.closest("[data-admin-delete-cycle]");
    if (!d) return;
    if (!confirm("¿Eliminar este perfil por ciclo y todos sus reportes asociados? (La cuenta del usuario se mantiene. Para borrar la cuenta completa usa «Eliminar cuenta» en Usuarios.)")) return;
    try {
      await request(
        "/rest/v1/applicant_cycles?id=eq." +
          encodeURIComponent(d.dataset.adminDeleteCycle),
        { method: "DELETE", prefer: "return=minimal" },
      );
      toast("Perfil eliminado.");
      await refresh();
    } catch (err) {
      toast(err.message, "bad");
    }
  });

  q("officialSearchBtn").addEventListener("click", () =>
    loadOfficialPrograms().catch((e) => toast(e.message, "bad")),
  );
  q("officialSearch").addEventListener("keydown", (e) => {
    if (e.key === "Enter")
      loadOfficialPrograms().catch((x) => toast(x.message, "bad"));
  });
  q("officialSpecialty").addEventListener("change", () =>
    loadOfficialPrograms().catch((e) => toast(e.message, "bad")),
  );
  q("refreshIntelligence").addEventListener("click", () => loadIntelligence());
  q("watchForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!session) return toast("Inicia sesión para crear alertas.", "bad");
    const f = Object.fromEntries(new FormData(e.target)),
      row = {
        user_id: session.user.id,
        specialty: f.specialty,
        state: (f.state || "").trim().toUpperCase() || null,
        enabled: true,
      };
    if (!row.specialty) return toast("Selecciona una especialidad.", "bad");
    if (row.state && !/^[A-Z]{2}$/.test(row.state))
      return toast("El estado debe ser el código de 2 letras (ej. FL).", "bad");
    try {
      await request("/rest/v1/program_watch_subscriptions", {
        method: "POST",
        body: row,
        prefer: "return=minimal",
      });
      toast("Alerta creada.");
      e.target.reset();
      await loadWatches();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("watchList").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-watch-delete]");
    if (!b) return;
    try {
      await request(
        "/rest/v1/program_watch_subscriptions?id=eq." +
          encodeURIComponent(b.dataset.watchDelete),
        { method: "DELETE", prefer: "return=minimal" },
      );
      toast("Alerta eliminada.");
      await loadWatches();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("notifications").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-notification-read]");
    if (!b) return;
    try {
      await request(
        "/rest/v1/notifications?id=eq." +
          encodeURIComponent(b.dataset.notificationRead),
        {
          method: "PATCH",
          body: { read_at: new Date().toISOString() },
          prefer: "return=minimal",
        },
      );
      await loadNotifications();
    } catch (err) {
      toast(err.message, "bad");
    }
  });
  q("browserNotify").addEventListener("click", async () => {
    if (!("Notification" in window))
      return toast("Este navegador no soporta notificaciones.", "bad");
    const p = await Notification.requestPermission();
    toast(
      p === "granted"
        ? "Alertas del navegador activadas."
        : "Permiso no concedido.",
      p === "granted" ? "good" : "bad",
    );
  });

  if ("serviceWorker" in navigator && location.protocol.startsWith("http"))
    navigator.serviceWorker.register("./service-worker.js").catch(() => {});
  (async () => {
    await consumeAuthRedirect();
    // Deep links such as #data or #account open the matching section.
    const start = hashView();
    if (!recoveryMode && start && q(start)?.classList.contains("view"))
      currentView = start;
    updateNav(true);
    await refresh();
    // If the selected Match cycle has no community data yet (e.g. the 2027
    // season just started), show the most recent cycle that does.
    if (cloudReady() && !publicDB.overview?.applicants && cycleVal() !== null) {
      const sel = q("globalCycle");
      const years = [...sel.options].map((o) => o.value).filter((v) => v !== "all").sort().reverse();
      for (const y of years) {
        if (y === sel.value) continue;
        try {
          const o = await rpc("community_overview", { p_cycle: Number(y) });
          if (o?.applicants) {
            sel.value = y;
            await refresh();
            break;
          }
        } catch {
          break;
        }
      }
    }
    if (currentView === "applicants") findSimilar();
    if (session) loadNotifications().catch(() => {});
  })();
  setInterval(() => {
    if (session && !document.hidden) loadNotifications().catch(() => {});
  }, 30000);
})();
