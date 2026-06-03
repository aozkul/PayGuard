import { defaultState } from "../data/defaults.js";

const storageKey = "azubipilot-web-state";

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

export function loadState() {
  const saved = window.localStorage.getItem(storageKey);
  if (!saved) {
    return deepClone(defaultState);
  }

  try {
    return { ...deepClone(defaultState), ...JSON.parse(saved) };
  } catch {
    return deepClone(defaultState);
  }
}

export function saveState(state) {
  window.localStorage.setItem(storageKey, JSON.stringify(state));
}
