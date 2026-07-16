"use strict";

const languageButtons = Array.from(document.querySelectorAll("[data-language]"));
const localizableElements = Array.from(document.querySelectorAll("[data-ru]"));
const ariaLocalizableElements = Array.from(
  document.querySelectorAll("[data-aria-ru]")
);
const altLocalizableElements = Array.from(
  document.querySelectorAll("[data-alt-ru]")
);
const copyButtons = Array.from(document.querySelectorAll("[data-copy-target]"));
const navigation = document.querySelector("[data-nav]");
const navigationToggle = document.querySelector("[data-nav-toggle]");
const storageKey = "megawhisper-site-language";

const pageMetadata = {
  en: {
    title: "MegaWhisper | Speech to text for Linux",
    description:
      "Private local and OpenAI-compatible speech transcription for the Linux desktop. Install MegaWhisper with Flatpak or run the portable AppImage.",
    openNavigation: "Open navigation",
    closeNavigation: "Close navigation",
  },
  ru: {
    title: "MegaWhisper | Речь в текст на Linux",
    description:
      "Приватная локальная и OpenAI-совместимая транскрибация речи на Linux. Установите MegaWhisper через Flatpak или запустите переносимый AppImage.",
    openNavigation: "Открыть навигацию",
    closeNavigation: "Закрыть навигацию",
  },
};

let currentLanguage = "en";

function storedLanguage() {
  try {
    const value = window.localStorage.getItem(storageKey);
    return value === "ru" ? "ru" : "en";
  } catch {
    return "en";
  }
}

function rememberLanguage(language) {
  try {
    window.localStorage.setItem(storageKey, language);
  } catch {
    // The page remains fully usable when browser storage is unavailable.
  }
}

function updateCopyButtonLabel(button, copied) {
  const label =
    currentLanguage === "ru"
      ? copied
        ? button.dataset.copiedLabelRu
        : button.dataset.copyLabelRu
      : copied
        ? button.dataset.copiedLabel
        : button.dataset.copyLabel;
  button.textContent = label || (currentLanguage === "ru" ? "Копировать" : "Copy");
  if (copied) {
    button.setAttribute(
      "aria-label",
      currentLanguage === "ru"
        ? button.dataset.copiedAriaLabelRu
        : button.dataset.copiedAriaLabel
    );
  } else {
    button.setAttribute(
      "aria-label",
      currentLanguage === "ru" ? button.dataset.ariaRu : button.dataset.ariaEn
    );
  }
}

function setNavigationState(open) {
  if (!navigation || !navigationToggle) {
    return;
  }
  navigation.dataset.open = open ? "true" : "false";
  navigationToggle.setAttribute("aria-expanded", open ? "true" : "false");
  navigationToggle.setAttribute(
    "aria-label",
    open
      ? pageMetadata[currentLanguage].closeNavigation
      : pageMetadata[currentLanguage].openNavigation
  );
}

function applyLanguage(language, persist) {
  currentLanguage = language === "ru" ? "ru" : "en";
  document.documentElement.lang = currentLanguage;

  for (const element of localizableElements) {
    if (!element.dataset.en) {
      element.dataset.en = element.textContent.trim();
    }
    element.textContent =
      currentLanguage === "ru" ? element.dataset.ru : element.dataset.en;
  }

  for (const element of ariaLocalizableElements) {
    if (!element.dataset.ariaEn) {
      element.dataset.ariaEn = element.getAttribute("aria-label") || "";
    }
    element.setAttribute(
      "aria-label",
      currentLanguage === "ru" ? element.dataset.ariaRu : element.dataset.ariaEn
    );
  }

  for (const element of altLocalizableElements) {
    if (!element.dataset.altEn) {
      element.dataset.altEn = element.getAttribute("alt") || "";
    }
    element.setAttribute(
      "alt",
      currentLanguage === "ru" ? element.dataset.altRu : element.dataset.altEn
    );
  }

  for (const button of languageButtons) {
    button.setAttribute(
      "aria-pressed",
      button.dataset.language === currentLanguage ? "true" : "false"
    );
  }

  for (const button of copyButtons) {
    updateCopyButtonLabel(button, false);
  }

  document.title = pageMetadata[currentLanguage].title;
  const description = document.querySelector('meta[name="description"]');
  if (description) {
    description.setAttribute("content", pageMetadata[currentLanguage].description);
  }

  setNavigationState(false);
  if (persist) {
    rememberLanguage(currentLanguage);
  }
}

async function copyCommand(button) {
  const targetId = button.dataset.copyTarget;
  const target = targetId ? document.getElementById(targetId) : null;
  if (!target) {
    return;
  }

  const text = target.textContent.trim();
  try {
    await navigator.clipboard.writeText(text);
    updateCopyButtonLabel(button, true);
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(target);
    selection.removeAllRanges();
    selection.addRange(range);
    target.focus?.();
  }
}

for (const button of languageButtons) {
  button.addEventListener("click", () => {
    applyLanguage(button.dataset.language, true);
  });
}

for (const button of copyButtons) {
  button.addEventListener("click", () => {
    void copyCommand(button);
  });
  button.addEventListener("blur", () => {
    updateCopyButtonLabel(button, false);
  });
}

if (navigationToggle) {
  navigationToggle.addEventListener("click", () => {
    const isOpen = navigation?.dataset.open === "true";
    setNavigationState(!isOpen);
  });
}

if (navigation) {
  for (const link of navigation.querySelectorAll("a")) {
    link.addEventListener("click", () => {
      setNavigationState(false);
    });
  }
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    setNavigationState(false);
  }
});

applyLanguage(storedLanguage(), false);
