export const cefrLevels = ["A0", "A1", "A2", "B1", "B2", "C1"];

export const applicationStatuses = [
  "Firma bulundu",
  "Basvuru hazirlaniyor",
  "Basvuru gonderildi",
  "Cevap bekleniyor",
  "Ek belge istendi",
  "Mulakat daveti",
  "Praktikum",
  "Kabul",
  "Ret",
];

export const boardStatuses = applicationStatuses;

export const sources = [
  {
    label: "Make it in Germany - Visa for vocational training",
    url: "https://www.make-it-in-germany.com/en/visa-residence/types/training",
  },
  {
    label: "Make it in Germany - Requirements for vocational training",
    url: "https://www.make-it-in-germany.com/en/study-vocational-training/training-in-germany/requirements-for-vocational-training",
  },
  {
    label: "Bundesagentur fur Arbeit - Undergoing vocational training in Germany",
    url: "https://www.arbeitsagentur.de/int/en/vocational-training",
  },
  {
    label: "BERUFENET - Ausbildungsvergutung",
    url: "https://web.arbeitsagentur.de/berufenet/bba/berufsausbildung/dualeausbildung/ausbildungsverguetung",
  },
  {
    label: "BIBB - Mindestausbildungsvergutung 2026",
    url: "https://www.bibb.de/de/199658.php",
  },
  {
    label: "Anerkennung in Deutschland - School-leaving certificates",
    url: "https://www.anerkennung-in-deutschland.de/html/en/recognition-school-leaving-certificates.php",
  },
  {
    label: "KMK/ZAB - Recognition of School Qualifications",
    url: "https://www.kmk.org/zab/central-office-for-foreign-education/general-information-about-recognition/recognition-of-school-qualifications.html",
  },
];

export const cityCosts = [
  { city: "Berlin", rent: [520, 780], deposit: [900, 1500], transport: [58, 58], food: [260, 360] },
  { city: "Hamburg", rent: [560, 820], deposit: [1000, 1600], transport: [58, 69], food: [270, 360] },
  { city: "Leipzig", rent: [360, 580], deposit: [700, 1200], transport: [49, 58], food: [240, 330] },
  { city: "Dortmund", rent: [390, 620], deposit: [750, 1250], transport: [49, 58], food: [250, 340] },
  { city: "Nurnberg", rent: [430, 680], deposit: [850, 1400], transport: [49, 58], food: [255, 345] },
  { city: "Stuttgart", rent: [600, 900], deposit: [1100, 1800], transport: [58, 70], food: [280, 380] },
];

export const documentTemplates = [
  { id: "passport", title: "Pasaport", category: "Kimlik", critical: true },
  { id: "biometric-photo", title: "Biyometrik fotograf", category: "Kimlik", critical: false },
  { id: "diploma", title: "Diploma", category: "Egitim", critical: true },
  { id: "transcript", title: "Transkript", category: "Egitim", critical: true },
  { id: "recognition", title: "Denklik / tanima kaydi", category: "Egitim", critical: false },
  { id: "german-certificate", title: "Almanca sertifikasi", category: "Dil", critical: true },
  { id: "cv", title: "Almanca CV", category: "Basvuru", critical: true },
  { id: "cover-letter", title: "Anschreiben", category: "Basvuru", critical: true },
  { id: "references", title: "Referanslar / staj belgeleri", category: "Basvuru", critical: false },
  { id: "contract", title: "Ausbildungsvertrag", category: "Vize", critical: true },
  { id: "insurance", title: "Saglik sigortasi", category: "Vize", critical: true },
  { id: "finance-proof", title: "Finansal kanit", category: "Vize", critical: true },
  { id: "housing", title: "Konaklama plani", category: "Vize", critical: true },
  { id: "translation", title: "Yeminli tercume / apostil", category: "Tercume", critical: false },
];

export const defaultState = {
  profile: {
    firstName: "Elif",
    lastName: "Yilmaz",
    userType: "turkiye_adayi",
    currentCountry: "Turkiye",
    currentCity: "Istanbul",
    age: 21,
    highestDegree: "Lise",
    schoolType: "Anadolu Lisesi",
    graduationYear: 2024,
    fieldOfStudy: "Sayisal",
    hasDiploma: true,
    hasTranscript: false,
    germanLevel: "A2",
    hasCertificate: false,
    englishLevel: "B1",
    interests: ["it", "teknik", "lojistik"],
    goals: ["teknik_kariyer", "guvenli_yol"],
    constraints: ["fiziksel_is_olur", "kucuk_sehir_olur"],
    shiftTolerance: 3,
    physicalTolerance: 4,
    customerComfort: 3,
    budget: 4500,
    hasPassport: true,
    hasHousingPlan: false,
  },
  selectedOccupationId: "fachinformatiker-anwendungsentwicklung",
  applications: [
    {
      id: "app-1",
      companyName: "Bosch Rexroth",
      occupationId: "mechatroniker",
      city: "Stuttgart",
      status: "Basvuru gonderildi",
      appliedAt: "2026-05-12",
      nextFollowUpAt: "2026-05-26",
      notes: "Takip maili gerekli.",
    },
    {
      id: "app-2",
      companyName: "DB Schenker",
      occupationId: "fachkraft-lagerlogistik",
      city: "Dortmund",
      status: "Cevap bekleniyor",
      appliedAt: "2026-05-05",
      nextFollowUpAt: "2026-05-20",
      notes: "Lojistik tarafi icin ikinci tercih.",
    },
  ],
  documents: documentTemplates.map((item) => ({
    ...item,
    done: ["passport", "diploma", "cv"].includes(item.id),
  })),
  finance: {
    city: "Berlin",
    monthlyBudget: 950,
    moveBudget: 4500,
  },
  risk: {
    guaranteePromise: true,
    highUpfrontFee: true,
    hasOfficialContract: false,
    professionalDomain: false,
    addressConsistent: false,
    unrealisticSalary: true,
    claimsNoGermanNeeded: true,
  },
};

export const emailTemplateKinds = [
  { id: "application", label: "Basvuru maili" },
  { id: "followup", label: "Takip maili" },
  { id: "interview", label: "Mulakat kabul maili" },
  { id: "documents", label: "Eksik belge maili" },
  { id: "housing", label: "Konaklama arama maili" },
  { id: "school", label: "Berufsschule bilgi maili" },
];
