import {
  applicationStatuses,
  boardStatuses,
  cefrLevels,
  cityCosts,
  sources,
} from "./data/defaults.js";
import { occupations } from "./data/occupations.js";
import { analyzeRisk, buildFamilyReport, computeFinancePlan, generateCoverLetter, generateCv, generateEmailTemplates, generatePriorityActions, generateRoadmap } from "./logic/generators.js";
import { computeReadiness, rankOccupations } from "./logic/scoring.js";
import { loadState, saveState } from "./state/store.js";

let state = loadState();

const occupationById = new Map(occupations.map((item) => [item.id, item]));

const profileFields = [
  { key: "firstName", label: "Ad", type: "text" },
  { key: "lastName", label: "Soyad", type: "text" },
  {
    key: "userType",
    label: "Kullanici tipi",
    type: "select",
    options: [
      ["turkiye_adayi", "Turkiye'deyim"],
      ["almanya_genci", "Almanya'dayim"],
      ["aile", "Cocugum icin bakiyorum"],
      ["danisman", "Danismanim"],
    ],
  },
  { key: "currentCity", label: "Bulundugun sehir", type: "text" },
  { key: "age", label: "Yas", type: "number", min: 16, max: 40 },
  {
    key: "highestDegree",
    label: "En yuksek egitim",
    type: "select",
    options: [
      ["Lise", "Lise"],
      ["Meslek Lisesi", "Meslek Lisesi"],
      ["On Lisans", "On Lisans"],
      ["Lisans", "Lisans"],
    ],
  },
  { key: "schoolType", label: "Okul tipi", type: "text" },
  { key: "fieldOfStudy", label: "Alan / bolum", type: "text" },
  {
    key: "germanLevel",
    label: "Almanca seviyesi",
    type: "select",
    options: cefrLevels.map((level) => [level, level]),
  },
  {
    key: "englishLevel",
    label: "Ingilizce seviyesi",
    type: "select",
    options: cefrLevels.slice(1).map((level) => [level, level]),
  },
  { key: "budget", label: "Ilk gelis butcesi (Euro)", type: "number", min: 0 },
];

const applicationFields = [
  { key: "companyName", label: "Firma adi", type: "text" },
  { key: "city", label: "Sehir", type: "text" },
  {
    key: "occupationId",
    label: "Meslek",
    type: "select",
    options: occupations.slice(0, 14).map((item) => [item.id, item.titleDE]),
  },
  {
    key: "status",
    label: "Durum",
    type: "select",
    options: applicationStatuses.map((item) => [item, item]),
  },
  { key: "appliedAt", label: "Basvuru tarihi", type: "date" },
  { key: "nextFollowUpAt", label: "Takip tarihi", type: "date" },
  { key: "notes", label: "Not", type: "textarea", full: true },
];

const financeFields = [
  {
    key: "city",
    label: "Hedef sehir",
    type: "select",
    options: cityCosts.map((item) => [item.city, item.city]),
  },
  { key: "moveBudget", label: "Baslangic butcesi", type: "number", min: 0 },
  { key: "monthlyBudget", label: "Aylik yasam butcesi", type: "number", min: 0 },
];

const riskFields = [
  { key: "guaranteePromise", label: "Is veya vize garantisi veriliyor" },
  { key: "highUpfrontFee", label: "Pesin yuksek ucret isteniyor" },
  { key: "hasOfficialContract", label: "Resmi sozlesme var" },
  { key: "professionalDomain", label: "Email domaini profesyonel" },
  { key: "addressConsistent", label: "Adres ve web sitesi tutarli" },
  { key: "unrealisticSalary", label: "Maas vaadi gercek disi" },
  { key: "claimsNoGermanNeeded", label: "Almanca gerekmiyor deniyor" },
];

function renderField(field, value) {
  if (field.type === "select") {
    return `
      <div class="field ${field.full ? "full" : ""}">
        <label for="${field.key}">${field.label}</label>
        <select id="${field.key}" name="${field.key}">
          ${field.options.map(([optionValue, optionLabel]) => `
            <option value="${optionValue}" ${optionValue === value ? "selected" : ""}>${optionLabel}</option>
          `).join("")}
        </select>
      </div>
    `;
  }

  if (field.type === "textarea") {
    return `
      <div class="field ${field.full ? "full" : ""}">
        <label for="${field.key}">${field.label}</label>
        <textarea id="${field.key}" name="${field.key}">${value || ""}</textarea>
      </div>
    `;
  }

  return `
    <div class="field ${field.full ? "full" : ""}">
      <label for="${field.key}">${field.label}</label>
      <input
        id="${field.key}"
        name="${field.key}"
        type="${field.type}"
        value="${value ?? ""}"
        ${field.min !== undefined ? `min="${field.min}"` : ""}
        ${field.max !== undefined ? `max="${field.max}"` : ""}
      />
    </div>
  `;
}

function renderCheckboxGroup(title, key, options, selected) {
  return `
    <div class="field full">
      <label>${title}</label>
      <div class="checkbox-grid">
        ${options.map(([value, label]) => `
          <label class="check-pill">
            <input type="checkbox" data-group="${key}" value="${value}" ${selected.includes(value) ? "checked" : ""} />
            <span>${label}</span>
          </label>
        `).join("")}
      </div>
    </div>
  `;
}

function getComputed() {
  const rankedOccupations = rankOccupations(state.profile, occupations);
  const readiness = computeReadiness(state.profile, state.documents, state.applications, rankedOccupations);
  const selectedOccupation = occupationById.get(state.selectedOccupationId) || rankedOccupations[0];
  const roadmap = generateRoadmap(state.profile, readiness, rankedOccupations);
  const priorityActions = generatePriorityActions(readiness, state.documents, rankedOccupations);
  const financePlan = computeFinancePlan(state.finance);
  const riskAnalysis = analyzeRisk(state.risk);
  const emailTemplates = generateEmailTemplates(state.profile, selectedOccupation);

  return {
    rankedOccupations,
    readiness,
    selectedOccupation,
    roadmap,
    priorityActions,
    financePlan,
    riskAnalysis,
    emailTemplates,
  };
}

function renderProfileForm() {
  const form = document.querySelector("#profile-form");
  form.innerHTML = `
    ${profileFields.map((field) => renderField(field, state.profile[field.key])).join("")}
    <div class="field">
      <label class="check-pill">
        <input type="checkbox" name="hasDiploma" ${state.profile.hasDiploma ? "checked" : ""} />
        <span>Diploma var</span>
      </label>
    </div>
    <div class="field">
      <label class="check-pill">
        <input type="checkbox" name="hasTranscript" ${state.profile.hasTranscript ? "checked" : ""} />
        <span>Transkript var</span>
      </label>
    </div>
    <div class="field">
      <label class="check-pill">
        <input type="checkbox" name="hasCertificate" ${state.profile.hasCertificate ? "checked" : ""} />
        <span>Almanca sertifikasi var</span>
      </label>
    </div>
    <div class="field">
      <label class="check-pill">
        <input type="checkbox" name="hasPassport" ${state.profile.hasPassport ? "checked" : ""} />
        <span>Pasaport hazir</span>
      </label>
    </div>
    <div class="field full">
      <label>Fiziksel calisma toleransi (${state.profile.physicalTolerance}/5)</label>
      <input type="range" min="1" max="5" name="physicalTolerance" value="${state.profile.physicalTolerance}" />
    </div>
    <div class="field full">
      <label>Musteri iletisim rahatligi (${state.profile.customerComfort}/5)</label>
      <input type="range" min="1" max="5" name="customerComfort" value="${state.profile.customerComfort}" />
    </div>
    ${renderCheckboxGroup("Ilgi alanlari", "interests", [
      ["it", "IT"],
      ["teknik", "Teknik"],
      ["lojistik", "Lojistik"],
      ["otelcilik", "Otelcilik"],
      ["saglik", "Saglik"],
      ["ofis", "Ofis"],
      ["satis", "Satis"],
      ["zanaat", "Zanaat"],
      ["sosyal", "Sosyal"],
    ], state.profile.interests)}
    ${renderCheckboxGroup("Hedefler", "goals", [
      ["hizli_gitmek", "Hizli gitmek"],
      ["yuksek_gelir", "Yuksek gelir"],
      ["teknik_kariyer", "Teknik kariyer"],
      ["guvenli_yol", "Guvenli yol"],
    ], state.profile.goals)}
    ${renderCheckboxGroup("Kisitlar / esneklik", "constraints", [
      ["fiziksel_is_olur", "Fiziksel is olabilir"],
      ["vardiya_olur", "Vardiya olabilir"],
      ["kucuk_sehir_olur", "Kucuk sehir olur"],
    ], state.profile.constraints)}
  `;
}

function renderMetrics(computed) {
  const metrics = [
    ["Hazirlik", `%${computed.readiness.total}`, `${computed.readiness.readyMonthsEstimate} aylik plan`],
    ["En guclu meslek", computed.rankedOccupations[0].titleDE, `%${computed.rankedOccupations[0].fitScore} uyum`],
    ["Belge durumu", `${state.documents.filter((item) => item.done).length}/${state.documents.length}`, "tamamlanan checklist"],
    ["Pipeline", `${state.applications.length} kayit`, `${state.applications.filter((item) => item.status === "Basvuru gonderildi").length} aktif gonderim`],
  ];

  document.querySelector("#metrics-grid").innerHTML = metrics.map(([label, value, detail]) => `
    <article class="metric-card">
      <p class="eyebrow">${label}</p>
      <strong>${value}</strong>
      <span>${detail}</span>
    </article>
  `).join("");

  document.querySelector("#hero-highlight").innerHTML = `
    <p class="eyebrow">Kisisel Ozet</p>
    <h3>%${computed.readiness.total} hazirlik</h3>
    <p>
      Su an icin en guclu yol: <strong>${computed.rankedOccupations[0].titleDE}</strong>.
      Tahmini hazir olma suresi <strong>${computed.readiness.readyMonthsEstimate} ay</strong>.
    </p>
    <div class="meta-tags">
      <span class="tag">Dil: ${state.profile.germanLevel}</span>
      <span class="tag alt">Butce: ${state.profile.budget} Euro</span>
      <span class="tag">Hedef: ${state.profile.goals[0]?.replaceAll("_", " ") || "netlestir"}</span>
    </div>
  `;

  document.querySelector("#priority-actions").innerHTML = computed.priorityActions.map((item) => `
    <div class="stack-item">
      <strong>${item.title}</strong>
      <p>${item.text}</p>
    </div>
  `).join("");

  document.querySelector("#hero-score").textContent = `Hazirlik ${computed.readiness.total}%`;
}

function renderPlan(computed) {
  document.querySelector("#score-breakdown").innerHTML = computed.readiness.breakdown.map((item) => `
    <div class="score-row">
      <header>
        <span>${item.label}</span>
        <span>${item.value}/100</span>
      </header>
      <div class="progress-track">
        <div class="progress-fill" style="width:${item.value}%"></div>
      </div>
    </div>
  `).join("");

  document.querySelector("#roadmap-list").innerHTML = computed.roadmap.map((item) => `
    <div class="timeline-item">
      <div class="timeline-badge">${item.month}</div>
      <div>
        ${item.tasks.map((task) => `<p>${task}</p>`).join("")}
      </div>
    </div>
  `).join("");
}

function renderOccupations(computed) {
  document.querySelector("#occupation-summary").innerHTML = `
    <p>Toplam ${occupations.length} meslekten en uygun 8 sonuc gosteriliyor.</p>
  `;

  document.querySelector("#occupation-cards").innerHTML = computed.rankedOccupations.slice(0, 8).map((item) => `
    <article class="occupation-card">
      <div class="occupation-top">
        <div>
          <p class="eyebrow">${item.category} / ${item.trainingType}</p>
          <h3>${item.titleDE}</h3>
          <p>${item.descriptionTR}</p>
        </div>
        <div class="occupation-score">${item.fitScore}%</div>
      </div>
      <div class="meta-tags">
        <span class="tag">Dil: ${item.requiredGermanLevel}-${item.preferredGermanLevel}</span>
        <span class="tag alt">Sure: ${(item.durationMonths / 12).toFixed(1)} yil</span>
        <span class="tag">Vize: ${item.visaRealism}/5</span>
      </div>
      <p><strong>Neden uygun:</strong> ${item.strengths.join(", ")}.</p>
      <p><strong>Dikkat:</strong> ${item.cons[0]}.</p>
      <button data-select-occupation="${item.id}" class="${item.id === state.selectedOccupationId ? "is-selected" : ""}">
        ${item.id === state.selectedOccupationId ? "Secili hedef meslek" : "Bunu hedef sec"}
      </button>
    </article>
  `).join("");
}

function renderApplications() {
  const form = document.querySelector("#application-form");
  form.innerHTML = `
    ${applicationFields.map((field) => renderField(field, field.key === "status" ? "Firma bulundu" : "")).join("")}
    <div class="field full">
      <button type="submit" class="primary-button">Basvuru ekle</button>
    </div>
  `;

  document.querySelector("#applications-board").innerHTML = boardStatuses.map((status) => `
    <section class="status-column">
      <h4>${status}</h4>
      ${state.applications.filter((item) => item.status === status).map((item) => `
        <article class="application-card">
          <strong>${item.companyName}</strong>
          <p>${occupationById.get(item.occupationId)?.titleDE || "-"}</p>
          <p>${item.city || ""} ${item.appliedAt ? `• ${item.appliedAt}` : ""}</p>
          <select data-application-status="${item.id}">
            ${applicationStatuses.map((option) => `
              <option value="${option}" ${option === item.status ? "selected" : ""}>${option}</option>
            `).join("")}
          </select>
        </article>
      `).join("") || "<p>Kayit yok.</p>"}
    </section>
  `).join("");
}

function renderDocuments() {
  const completed = state.documents.filter((item) => item.done).length;
  document.querySelector("#documents-summary").textContent = `${completed}/${state.documents.length} belge hazir`;
  document.querySelector("#documents-grid").innerHTML = state.documents.map((item) => `
    <article class="document-card">
      <header>
        <div>
          <strong>${item.title}</strong>
          <p>${item.category}</p>
        </div>
        <span class="tag ${item.critical ? "alt" : ""}">${item.critical ? "Kritik" : "Opsiyonel"}</span>
      </header>
      <label class="document-toggle">
        <input type="checkbox" data-document-id="${item.id}" ${item.done ? "checked" : ""} />
        <span>${item.done ? "Hazir" : "Eksik"}</span>
      </label>
    </article>
  `).join("");
}

function renderToolkit(computed) {
  document.querySelector("#cv-output").innerHTML = generateCv(state.profile, computed.selectedOccupation);
  document.querySelector("#cover-letter-output").innerHTML = generateCoverLetter(state.profile, computed.selectedOccupation);
  document.querySelector("#email-templates").innerHTML = computed.emailTemplates.map((item) => `
    <article class="email-card">
      <h4>${item.label}</h4>
      <pre>${item.body}</pre>
    </article>
  `).join("");
}

function renderFamily(computed) {
  document.querySelector("#family-report").innerHTML = buildFamilyReport(
    state.profile,
    computed.readiness,
    computed.rankedOccupations,
    computed.financePlan,
    computed.riskAnalysis,
  );
}

function renderFinance(computed) {
  document.querySelector("#finance-form").innerHTML = `
    ${financeFields.map((field) => renderField(field, state.finance[field.key])).join("")}
  `;
  document.querySelector("#finance-output").innerHTML = computed.financePlan.notes.map((note) => `
    <div class="stack-item"><p>${note}</p></div>
  `).join("") + `
    <div class="stack-item">
      <strong>Onerilen ilk gelis tamponu: ${computed.financePlan.recommendedMoveBudget} Euro</strong>
      <p>Mevcut fark: ${computed.financePlan.budgetGap} Euro</p>
    </div>
  `;

  document.querySelector("#risk-form").innerHTML = riskFields.map((field) => `
    <div class="field full">
      <label class="check-pill">
        <input type="checkbox" name="${field.key}" ${state.risk[field.key] ? "checked" : ""} />
        <span>${field.label}</span>
      </label>
    </div>
  `).join("");

  document.querySelector("#risk-output").innerHTML = `
    <div class="stack-item">
      <strong>${computed.riskAnalysis.label} - ${computed.riskAnalysis.score}/100</strong>
      <p>${computed.riskAnalysis.summary}</p>
    </div>
  `;
}

function renderSources() {
  document.querySelector("#sources-list").innerHTML = sources.map((item) => `
    <li><a href="${item.url}" target="_blank" rel="noreferrer">${item.label}</a></li>
  `).join("");
}

function render() {
  const computed = getComputed();
  renderProfileForm();
  renderMetrics(computed);
  renderPlan(computed);
  renderOccupations(computed);
  renderApplications();
  renderDocuments();
  renderToolkit(computed);
  renderFamily(computed);
  renderFinance(computed);
  renderSources();
  saveState(state);
}

function handleProfileInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement)) {
    return;
  }

  if (target.dataset.group) {
    const group = target.dataset.group;
    const current = new Set(state.profile[group]);
    if (target.checked) current.add(target.value);
    else current.delete(target.value);
    state.profile[group] = [...current];
    render();
    return;
  }

  if (target.type === "checkbox") {
    state.profile[target.name] = target.checked;
  } else if (target.type === "number" || target.type === "range") {
    state.profile[target.name] = Number(target.value);
  } else {
    state.profile[target.name] = target.value;
  }

  render();
}

function handleFinanceInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) {
    return;
  }

  state.finance[target.name] = target.type === "number" ? Number(target.value) : target.value;
  render();
}

function handleRiskInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLInputElement)) {
    return;
  }

  state.risk[target.name] = target.checked;
  render();
}

function handleApplicationSubmit(event) {
  event.preventDefault();
  const formData = new FormData(event.currentTarget);
  const application = Object.fromEntries(formData.entries());

  state.applications = [
    {
      id: `app-${Date.now()}`,
      companyName: application.companyName || "Yeni firma",
      city: application.city || "",
      occupationId: application.occupationId || state.selectedOccupationId,
      status: application.status || "Firma bulundu",
      appliedAt: application.appliedAt || "",
      nextFollowUpAt: application.nextFollowUpAt || "",
      notes: application.notes || "",
    },
    ...state.applications,
  ];

  render();
}

function bindEvents() {
  document.querySelectorAll(".nav-link").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelectorAll(".nav-link").forEach((item) => item.classList.remove("is-active"));
      document.querySelectorAll(".panel-section").forEach((item) => item.classList.remove("is-visible"));
      button.classList.add("is-active");
      document.querySelector(`#${button.dataset.section}`)?.classList.add("is-visible");
    });
  });

  document.body.addEventListener("input", (event) => {
    const target = event.target;
    const profileForm = document.querySelector("#profile-form");
    const financeForm = document.querySelector("#finance-form");
    const riskForm = document.querySelector("#risk-form");

    if (profileForm?.contains(target)) handleProfileInput(event);
    if (financeForm?.contains(target)) handleFinanceInput(event);
    if (riskForm?.contains(target)) handleRiskInput(event);
  });

  document.body.addEventListener("change", (event) => {
    const target = event.target;

    if (target instanceof HTMLInputElement && target.dataset.documentId) {
      state.documents = state.documents.map((item) => (
        item.id === target.dataset.documentId ? { ...item, done: target.checked } : item
      ));
      render();
    }

    if (target instanceof HTMLSelectElement && target.dataset.applicationStatus) {
      state.applications = state.applications.map((item) => (
        item.id === target.dataset.applicationStatus ? { ...item, status: target.value } : item
      ));
      render();
    }
  });

  document.body.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    if (target.dataset.selectOccupation) {
      state.selectedOccupationId = target.dataset.selectOccupation;
      render();
    }
  });

  document.body.addEventListener("submit", (event) => {
    if (event.target instanceof HTMLFormElement && event.target.id === "application-form") {
      handleApplicationSubmit(event);
    }
  });
}

bindEvents();
render();
