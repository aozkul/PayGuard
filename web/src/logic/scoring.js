import { cefrLevels } from "../data/defaults.js";

const levelIndex = (level) => Math.max(0, cefrLevels.indexOf(level));

const educationBaseScores = {
  Ortaokul: 25,
  Lise: 58,
  "Meslek Lisesi": 68,
  "On Lisans": 74,
  Lisans: 80,
};

const goalBonus = {
  teknik_kariyer: { Teknik: 10, IT: 10, Zanaat: 8, Lojistik: 4 },
  guvenli_yol: { Lojistik: 8, Saglik: 10, Teknik: 8 },
  hizli_gitmek: { Lojistik: 8, Gastronomi: 8, Satis: 6 },
  yuksek_gelir: { IT: 10, Teknik: 8, Saglik: 7 },
};

function normalizeScore(value) {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function interestMatch(profile, occupation) {
  const total = occupation.interestTags.reduce((sum, tag) => (
    profile.interests.includes(tag) ? sum + 25 : sum
  ), 20);
  return normalizeScore(total);
}

function languageFit(profile, occupation) {
  const diff = levelIndex(profile.germanLevel) - levelIndex(occupation.requiredGermanLevel);
  const base = diff >= 0 ? 78 : 78 + (diff * 18);
  const certificateBonus = profile.hasCertificate ? 8 : 0;
  return normalizeScore(base + certificateBonus);
}

function educationFit(profile, occupation) {
  const education = educationBaseScores[profile.highestDegree] || 45;
  const documentBonus = (profile.hasDiploma ? 10 : 0) + (profile.hasTranscript ? 8 : 0);
  const fieldBonus = profile.fieldOfStudy.toLowerCase().includes("sayisal") &&
    ["IT", "Teknik"].includes(occupation.category) ? 8 : 0;
  return normalizeScore(education + documentBonus + fieldBonus);
}

function skillFit(profile, occupation) {
  const physicalDelta = Math.abs((profile.physicalTolerance || 3) - occupation.physicalWorkLevel);
  const customerDelta = Math.abs((profile.customerComfort || 3) - occupation.customerContactLevel);
  const score = 100 - (physicalDelta * 14) - (customerDelta * 10);
  return normalizeScore(score);
}

function constraintFit(profile, occupation) {
  let score = 76;
  if (!profile.constraints.includes("fiziksel_is_olur") && occupation.physicalWorkLevel >= 4) {
    score -= 24;
  }
  if (!profile.constraints.includes("vardiya_olur") && occupation.shiftWorkLikelihood >= 4) {
    score -= 22;
  }
  if (!profile.constraints.includes("kucuk_sehir_olur") && ["Lojistik", "Zanaat"].includes(occupation.category)) {
    score -= 10;
  }
  return normalizeScore(score);
}

function visaRealism(profile, occupation) {
  let score = occupation.visaRealism * 20;
  if (!profile.hasPassport) score -= 24;
  if (!profile.hasHousingPlan) score -= 10;
  return normalizeScore(score);
}

function marketDemand(occupation) {
  return normalizeScore(occupation.marketDemand * 20);
}

function longTermPotential(occupation) {
  return normalizeScore(occupation.longTermPotential * 20);
}

function goalAlignment(profile, occupation) {
  return (profile.goals || []).reduce((score, goal) => (
    score + ((goalBonus[goal] && goalBonus[goal][occupation.category]) || 0)
  ), 0);
}

export function rankOccupations(profile, occupations) {
  return occupations.map((occupation) => {
    const score =
      interestMatch(profile, occupation) * 0.2 +
      languageFit(profile, occupation) * 0.2 +
      educationFit(profile, occupation) * 0.15 +
      skillFit(profile, occupation) * 0.15 +
      constraintFit(profile, occupation) * 0.1 +
      visaRealism(profile, occupation) * 0.1 +
      marketDemand(occupation) * 0.05 +
      longTermPotential(occupation) * 0.05 +
      goalAlignment(profile, occupation) * 0.1;

    return {
      ...occupation,
      fitScore: normalizeScore(score),
      strengths: [
        interestMatch(profile, occupation) > 70 ? "Ilgi alani uyumlu" : "Ilgi uyumu orta",
        languageFit(profile, occupation) > 70 ? "Dil seviyesi yaklasiyor" : "Dil seviyesi gelistirilmeli",
        visaRealism(profile, occupation) > 70 ? "Non-EU gercekçiligi iyi" : "Vize realistligi dikkat istiyor",
      ],
    };
  }).sort((left, right) => right.fitScore - left.fitScore);
}

export function computeReadiness(profile, documents, applications, rankedOccupations) {
  const completedDocs = documents.filter((item) => item.done).length;
  const passportAndDocs = (profile.hasPassport ? 15 : 0) + (completedDocs / documents.length) * 85;
  const germanScore = normalizeScore(levelIndex(profile.germanLevel) * 18 + (profile.hasCertificate ? 12 : 0));
  const educationScore = educationFit(profile, rankedOccupations[0] || rankedOccupations);
  const documentScore = normalizeScore(passportAndDocs);
  const occupationScore = rankedOccupations[0]?.fitScore || 0;
  const applicationScore = normalizeScore((applications.length * 16) + (applications.some((item) => item.status === "Basvuru gonderildi") ? 15 : 0));
  const visaScore = normalizeScore((profile.hasPassport ? 38 : 0) + (profile.hasHousingPlan ? 24 : 0) + (documents.some((item) => item.id === "finance-proof" && item.done) ? 20 : 0));
  const financeScore = normalizeScore((profile.budget >= 4000 ? 70 : 45) + (profile.budget >= 6000 ? 15 : 0));
  const realismScore = normalizeScore(((rankedOccupations[0]?.visaRealism || 0) * 12) + (levelIndex(profile.germanLevel) >= 3 ? 25 : 10));

  const breakdown = [
    { label: "Almanca", value: germanScore, weight: 20 },
    { label: "Egitim", value: educationScore, weight: 15 },
    { label: "Belgeler", value: documentScore, weight: 15 },
    { label: "Meslek Uyumu", value: occupationScore, weight: 20 },
    { label: "Basvuru Hazirligi", value: applicationScore, weight: 10 },
    { label: "Vize Hazirligi", value: visaScore, weight: 10 },
    { label: "Finans", value: financeScore, weight: 5 },
    { label: "Gercekcilik", value: realismScore, weight: 5 },
  ];

  const total = normalizeScore(breakdown.reduce((sum, item) => sum + ((item.value * item.weight) / 100), 0));

  return {
    total,
    breakdown,
    readyMonthsEstimate: total >= 75 ? 3 : total >= 55 ? 5 : 7,
  };
}
