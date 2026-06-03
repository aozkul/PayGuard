import { cityCosts, emailTemplateKinds } from "../data/defaults.js";

export function generateRoadmap(profile, readiness, topOccupations) {
  const topTitle = topOccupations[0]?.titleDE || "hedef meslek";
  const needsCertificate = !profile.hasCertificate;
  const months = [
    {
      month: "Ay 1",
      tasks: [
        `${topTitle} icin hedef meslek secimini netlestir.`,
        "CV taslagini tamamla ve diploma/transkript klasorunu duzenle.",
        needsCertificate ? "B1 sinav tarihi arastir ve kurs planini sabitle." : "Mevcut sertifikayi profile ekle ve gecerliligini kontrol et.",
      ],
    },
    {
      month: "Ay 2",
      tasks: [
        "20 firma listesi cikar.",
        "Ilk 3 Anschreiben versiyonunu hazirla.",
        "Meslege ozel Almanca kelime listesiyle gunluk tekrar planla.",
      ],
    },
    {
      month: "Ay 3",
      tasks: [
        "Ilk 15-30 basvuruyu gonder.",
        "Takip mailleri icin tarihleri pipeline'a isle.",
        "Mulakat sorularina yazili cevap provasi yap.",
      ],
    },
    {
      month: "Ay 4",
      tasks: [
        "Ikinci basvuru dalgasini baslat.",
        "Eksik belge ve tercume durumunu tamamla.",
        "Kontrat ve vize checklist'ini aktif hale getir.",
      ],
    },
    {
      month: "Ay 5",
      tasks: [
        "Mulakatlar ve deneme gunleri icin mini hazirlik dosyasi cikar.",
        "Konaklama ve saglik sigortasi seceneklerini karsilastir.",
        "Aile ile finansal planin son halini paylas.",
      ],
    },
    {
      month: "Ay 6",
      tasks: [
        readiness.total >= 70 ? "Vize randevu hazirligini baslat." : "Readiness score 70+ hedefi icin eksik maddeleri kapat.",
        "Belgelerin PDF kopyalarini tek klasorde duzenle.",
        "Almanya giris checklist'ini son kez kontrol et.",
      ],
    },
  ];

  return months;
}

export function generatePriorityActions(readiness, documents, rankedOccupations) {
  const actions = [];
  const missingDocs = documents.filter((item) => item.critical && !item.done);

  if (readiness.breakdown[0].value < 65) {
    actions.push({
      title: "Almanca hedefini yukseltilmeli",
      text: "B1 seviyesine cikis bu profil icin en buyuk hizlandirici kaldirac.",
    });
  }

  if (missingDocs.length > 0) {
    actions.push({
      title: "Kritik belgeler eksik",
      text: `${missingDocs.slice(0, 3).map((item) => item.title).join(", ")} tamamlanmali.`,
    });
  }

  actions.push({
    title: "Hedef meslek listesi daraltilmali",
    text: `Su an en guclu adaylik alanlari: ${rankedOccupations.slice(0, 3).map((item) => item.titleDE).join(", ")}.`,
  });

  return actions;
}

export function generateCv(profile, occupation) {
  const fullName = `${profile.firstName} ${profile.lastName}`;

  return `
    <h4>${fullName}</h4>
    <p><strong>Hedef:</strong> ${occupation.titleDE} Ausbildung basvurusu</p>
    <p><strong>Profil:</strong> ${profile.currentCity}, ${profile.currentCountry} merkezli; ${profile.highestDegree} mezunu ve Almanca seviyesi ${profile.germanLevel} olan aday.</p>
    <p><strong>Guclu Yonler:</strong> ${profile.interests.join(", ")} odaklari; disiplinli hazirlik, belge takibi ve Almanya'da uzun vadeli kariyer hedefi.</p>
    <p><strong>Egitim:</strong> ${profile.schoolType} / ${profile.fieldOfStudy} - mezuniyet yili ${profile.graduationYear}</p>
    <p><strong>Diller:</strong> Almanca ${profile.germanLevel}${profile.hasCertificate ? " (sertifikali)" : ""}, Ingilizce ${profile.englishLevel}</p>
    <p><strong>Not:</strong> Bu taslak PDF export ve meslege gore varyasyon mantigi icin temel cerceveyi temsil eder.</p>
  `;
}

export function generateCoverLetter(profile, occupation) {
  return `
    <h4>${occupation.titleDE} icin Anschreiben taslagi</h4>
    <p>Sehr geehrte Damen und Herren,</p>
    <p>
      ich mochte mich fur eine Ausbildung als ${occupation.titleDE} bewerben.
      Ich komme aus der Turkei und bereite mich gezielt auf meinen Ausbildungsweg in Deutschland vor.
      Besonders interessieren mich ${profile.interests.join(", ")} Themen, deshalb passt dieses Berufsbild sehr gut zu meinem Profil.
    </p>
    <p>
      Zurzeit verfuge ich uber Deutschkenntnisse auf dem Niveau ${profile.germanLevel}
      ${profile.hasCertificate ? " und kann dies mit einem Zertifikat belegen." : " und arbeite aktiv auf ein B1-Zertifikat hin."}
      Ich bin motiviert, lernbereit und plane meinen Einstieg strukturiert mit klaren Schritten.
    </p>
    <p>
      Uber die Moglichkeit, mich personlich vorzustellen, wurde ich mich sehr freuen.
    </p>
    <p>Mit freundlichen Grussen<br />${profile.firstName} ${profile.lastName}</p>
    <p><strong>Turkce not:</strong> Metin, adayin dil seviyesini abartmadan sade ve guvenli tutuldu.</p>
  `;
}

export function generateEmailTemplates(profile, occupation) {
  return emailTemplateKinds.map((item) => {
    const templates = {
      application: `Betreff: Bewerbung um eine Ausbildung als ${occupation.titleDE}\n\nSehr geehrte Damen und Herren,\nim Anhang finden Sie meine Bewerbungsunterlagen fur die Ausbildung als ${occupation.titleDE}.\nIch freue mich uber eine Ruckmeldung.\n\nMit freundlichen Grussen\n${profile.firstName} ${profile.lastName}`,
      followup: `Betreff: Nachfrage zu meiner Bewerbung\n\nGuten Tag,\nich wollte freundlich nachfragen, ob meine Bewerbung fur die Ausbildung als ${occupation.titleDE} bei Ihnen eingegangen ist.\nVielen Dank fur Ihre Zeit.\n\nFreundliche Grusse\n${profile.firstName} ${profile.lastName}`,
      interview: `Betreff: Bestatigung des Vorstellungsgesprachs\n\nVielen Dank fur Ihre Einladung.\nHiermit bestatige ich den vorgeschlagenen Termin gerne.\n\nMit freundlichen Grussen\n${profile.firstName} ${profile.lastName}`,
      documents: `Betreff: Nachreichung der angeforderten Unterlagen\n\nanbei sende ich die angeforderten Unterlagen fur meine Bewerbung als ${occupation.titleDE}.\nBitte geben Sie mir Bescheid, falls weitere Dokumente benotigt werden.\n\nMit freundlichen Grussen\n${profile.firstName} ${profile.lastName}`,
      housing: `Betreff: Anfrage zu einer Unterkunftsmoglichkeit\n\nich beginne voraussichtlich meine Ausbildung in Deutschland und suche eine Unterkunft in Ihrem Ort.\nUber Informationen zu einem Zimmer oder Wohnheim wurde ich mich freuen.\n\nViele Grusse\n${profile.firstName} ${profile.lastName}`,
      school: `Betreff: Frage zur Berufsschule im Rahmen der Ausbildung\n\nich interessiere mich fur die Ausbildung als ${occupation.titleDE} und mochte gerne wissen, welche Unterlagen fur den Schulteil wichtig sind.\nVielen Dank im Voraus.\n\nMit freundlichen Grussen\n${profile.firstName} ${profile.lastName}`,
    };

    return {
      ...item,
      body: templates[item.id],
    };
  });
}

export function buildFamilyReport(profile, readiness, topOccupations, financePlan, risk) {
  const topList = topOccupations.slice(0, 3).map((item) => item.titleDE).join(", ");
  return `
    <h4>Aile Icin Ozet Durum</h4>
    <p><strong>Hazirlik skoru:</strong> %${readiness.total}. Tahmini hazir olma suresi ${readiness.readyMonthsEstimate} ay.</p>
    <p><strong>Aday profili:</strong> ${profile.age} yasinda, ${profile.highestDegree} mezunu, Almanca seviyesi ${profile.germanLevel}.</p>
    <p><strong>En uygun meslekler:</strong> ${topList}.</p>
    <p><strong>Maliyet tahmini:</strong> ${financePlan.city} icin aylik yasam gideri ortalama ${financePlan.monthlyRange} Euro araliginda. Ilk gelis butcesi icin tavsiye edilen tampon: ${financePlan.recommendedMoveBudget} Euro.</p>
    <p><strong>Riskler:</strong> ${risk.summary}</p>
    <p><strong>Ailenin rolu:</strong> belge duzeni, moral destegi, sinav/plansal takip ve baslangic finansmanini birlikte yonetmek.</p>
  `;
}

export function computeFinancePlan(finance) {
  const cityInfo = cityCosts.find((item) => item.city === finance.city) || cityCosts[0];
  const monthlyLow = cityInfo.rent[0] + cityInfo.transport[0] + cityInfo.food[0] + 45;
  const monthlyHigh = cityInfo.rent[1] + cityInfo.transport[1] + cityInfo.food[1] + 70;
  const recommendedMoveBudget = cityInfo.deposit[1] + monthlyHigh + 900;

  return {
    city: cityInfo.city,
    monthlyRange: `${monthlyLow}-${monthlyHigh}`,
    recommendedMoveBudget,
    budgetGap: finance.moveBudget - recommendedMoveBudget,
    notes: [
      `Oda kira tahmini: ${cityInfo.rent[0]}-${cityInfo.rent[1]} Euro`,
      `Depozito tahmini: ${cityInfo.deposit[0]}-${cityInfo.deposit[1]} Euro`,
      `Ulasim: ${cityInfo.transport[0]}-${cityInfo.transport[1]} Euro`,
      finance.moveBudget >= recommendedMoveBudget
        ? "Baslangic butcesi makul gorunuyor."
        : "Baslangic butcesi dar; aile tamponu veya ek birikim planlanmali.",
    ],
  };
}

export function analyzeRisk(risk) {
  let score = 100;
  if (risk.guaranteePromise) score -= 20;
  if (risk.highUpfrontFee) score -= 18;
  if (!risk.hasOfficialContract) score -= 16;
  if (!risk.professionalDomain) score -= 12;
  if (!risk.addressConsistent) score -= 12;
  if (risk.unrealisticSalary) score -= 12;
  if (risk.claimsNoGermanNeeded) score -= 18;

  const normalized = Math.max(0, score);
  let label = "Dusuk risk";
  if (normalized < 75) label = "Orta risk";
  if (normalized < 50) label = "Yuksek risk";

  const summary = normalized < 50
    ? "Birden fazla scam sinyali var. Resmi sozlesme ve kurum dogrulama olmadan ilerlenmemeli."
    : normalized < 75
      ? "Bazi sinyaller sorunlu. Sozlesme, email domaini ve adres teyidi gerekir."
      : "Buyuk bir kirmizi bayrak yok ancak yine de resmi kaynaklardan kontrol edilmeli.";

  return { score: normalized, label, summary };
}
