(() => {
  "use strict";

  const root = document.documentElement;
  const configuredRepository = root.dataset.repository || "";
  const repositoryReady = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(configuredRepository);

  if (repositoryReady) {
    document.querySelectorAll("[data-repo-link]").forEach((link) => {
      link.href = configuredRepository;
    });
    document.querySelectorAll("[data-download-link]").forEach((link) => {
      link.href = `${configuredRepository}/releases/download/v0.1.0/windows-linux-workstation-v0.1.0.zip`;
    });
    document.querySelectorAll("[data-security-link]").forEach((link) => {
      link.href = `${configuredRepository}/blob/main/SECURITY.md`;
    });
    document.querySelectorAll("[data-license-link]").forEach((link) => {
      link.href = `${configuredRepository}/blob/main/LICENSE`;
    });
    const cloneCommand = document.querySelector("[data-clone-command]");
    if (cloneCommand) cloneCommand.textContent = `git clone ${configuredRepository}.git`;
  } else {
    document.querySelectorAll("a[href*='__REPO_URL__']").forEach((link) => {
      link.href = "#install";
    });
  }

  const header = document.querySelector("[data-header]");
  const updateHeader = () => header?.classList.toggle("scrolled", window.scrollY > 12);
  updateHeader();
  window.addEventListener("scroll", updateHeader, { passive: true });

  const navToggle = document.querySelector(".nav-toggle");
  const siteNav = document.querySelector(".site-nav");
  navToggle?.addEventListener("click", () => {
    const open = navToggle.getAttribute("aria-expanded") === "true";
    navToggle.setAttribute("aria-expanded", String(!open));
    siteNav?.classList.toggle("open", !open);
  });
  siteNav?.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      navToggle?.setAttribute("aria-expanded", "false");
      siteNav.classList.remove("open");
    });
  });

  const tabs = Array.from(document.querySelectorAll("[data-tab]"));
  const panels = Array.from(document.querySelectorAll("[data-panel]"));
  const activateTab = (selected) => {
    tabs.forEach((tab) => {
      const active = tab === selected;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    panels.forEach((panel) => {
      const active = panel.dataset.panel === selected.dataset.tab;
      panel.hidden = !active;
      panel.classList.toggle("active", active);
    });
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => activateTab(tab));
    tab.addEventListener("keydown", (event) => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      let nextIndex = index;
      if (event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
      if (event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
      if (event.key === "Home") nextIndex = 0;
      if (event.key === "End") nextIndex = tabs.length - 1;
      tabs[nextIndex].focus();
      activateTab(tabs[nextIndex]);
    });
  });

  const demoDisable = document.querySelector("[data-demo-disable]");
  const demoStatus = document.querySelector("[data-demo-status]");
  const demoMessage = document.querySelector("[data-demo-message]");
  demoDisable?.addEventListener("click", () => {
    const disabled = demoStatus?.classList.toggle("disabled") ?? false;
    if (demoStatus) demoStatus.textContent = disabled ? "Disabled" : "Running";
    demoDisable.textContent = disabled ? "Restore background" : "Disable background";
    if (demoMessage) {
      demoMessage.textContent = disabled
        ? "Demo state: known automatic launch sources would be removed and the app stopped."
        : "Demo state restored. Nothing on your computer was changed."
    }
  });

  const formatRuntime = (hours) => {
    const wholeHours = Math.floor(hours);
    const minutes = Math.round((hours - wholeHours) * 60);
    return `${wholeHours}h ${String(minutes).padStart(2, "0")}m`;
  };

  const calculateButton = document.querySelector("[data-calculate]");
  calculateButton?.addEventListener("click", () => {
    const capacity = Number(document.querySelector("[data-capacity]")?.value);
    const before = Number(document.querySelector("[data-before]")?.value);
    const after = Number(document.querySelector("[data-after]")?.value);
    const output = document.querySelector("[data-calculator-output]");
    if (!output) return;

    output.classList.remove("positive", "negative");
    if (![capacity, before, after].every((value) => Number.isFinite(value) && value > 0)) {
      output.textContent = "Enter positive capacity, before-draw, and after-draw values.";
      return;
    }

    const beforeHours = capacity / before;
    const afterHours = capacity / after;
    const difference = afterHours - beforeHours;
    const percent = (difference / beforeHours) * 100;
    const sign = difference >= 0 ? "+" : "";
    output.classList.add(difference >= 0 ? "positive" : "negative");
    output.textContent = `Before ${formatRuntime(beforeHours)} / after ${formatRuntime(afterHours)} / ${sign}${Math.round(difference * 60)} min (${sign}${percent.toFixed(1)}%).`;
  });

  const copyStatus = document.querySelector("[data-copy-status]");
  const copyText = async (text) => {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.append(area);
    area.select();
    document.execCommand("copy");
    area.remove();
  };

  document.querySelectorAll("[data-copy-target]").forEach((button) => {
    button.addEventListener("click", async () => {
      const target = document.querySelector(button.dataset.copyTarget);
      if (!target) return;
      try {
        await copyText(target.textContent.trim());
        if (copyStatus) copyStatus.textContent = "Copied to clipboard.";
        const original = button.textContent;
        button.textContent = "Copied";
        window.setTimeout(() => { button.textContent = original; }, 1400);
      } catch {
        if (copyStatus) copyStatus.textContent = "Copy was blocked. Select the command manually.";
      }
    });
  });

  const faqItems = Array.from(document.querySelectorAll(".faq details"));
  faqItems.forEach((item) => {
    item.addEventListener("toggle", () => {
      if (!item.open) return;
      faqItems.filter((other) => other !== item).forEach((other) => { other.open = false; });
    });
  });
})();
