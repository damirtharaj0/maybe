import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { userPreference: String };

  connect() {
    // Inline <script> in <head> already owns initial theme application before first paint.
    // We only need to start listening for OS-level theme changes here.
    this.startSystemThemeListener();
    this.connected = true;
  }

  disconnect() {
    this.stopSystemThemeListener();
    this.connected = false;
  }

  // Called automatically by Stimulus when the userPreferenceValue changes (e.g., after form submit/page reload).
  // Skip the initial callback fired on connect — the inline script already set the correct theme.
  userPreferenceValueChanged() {
    if (!this.connected) return;
    this.applyTheme();
  }

  // Called when a theme radio button is clicked
  updateTheme(event) {
    const selectedTheme = event.currentTarget.value;
    if (selectedTheme === "system") {
      this.setTheme(this.systemPrefersDark());
    } else if (selectedTheme === "dark") {
      this.setTheme(true);
    } else {
      this.setTheme(false);
    }
  }

  // Applies theme based on the userPreferenceValue (from server)
  applyTheme() {
    if (this.userPreferenceValue === "system") {
      this.setTheme(this.systemPrefersDark());
    } else if (this.userPreferenceValue === "dark") {
      this.setTheme(true);
    } else {
      this.setTheme(false);
    }
  }

  // Sets or removes the data-theme attribute
  setTheme(isDark) {
    if (isDark) {
      document.documentElement.setAttribute("data-theme", "dark");
    } else {
      document.documentElement.setAttribute("data-theme", "light");
    }
  }

  systemPrefersDark() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  handleSystemThemeChange = (event) => {
    // Only apply system theme changes if the user preference is currently 'system'
    if (this.userPreferenceValue === "system") {
      this.setTheme(event.matches);
    }
  };

  toggle() {
    const currentTheme = document.documentElement.getAttribute("data-theme");
    if (currentTheme === "dark") {
      this.setTheme(false);
    } else {
      this.setTheme(true);
    }
  }

  startSystemThemeListener() {
    this.darkMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    this.darkMediaQuery.addEventListener(
      "change",
      this.handleSystemThemeChange,
    );
  }

  stopSystemThemeListener() {
    if (this.darkMediaQuery) {
      this.darkMediaQuery.removeEventListener(
        "change",
        this.handleSystemThemeChange,
      );
    }
  }
}
