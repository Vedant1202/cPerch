// cPerch site — theme toggle + copy-to-clipboard.
// The FOUC-safe initial theme is applied by a tiny inline script in each page's <head>;
// this file only wires up the interactive controls.

(function () {
  var root = document.documentElement;

  function resolvedTheme() {
    var pinned = root.getAttribute("data-theme");
    if (pinned === "light" || pinned === "dark") return pinned;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  var toggle = document.getElementById("theme-toggle");
  if (toggle) {
    function syncLabel() {
      var isDark = resolvedTheme() === "dark";
      toggle.setAttribute("aria-label", isDark ? "Switch to light theme" : "Switch to dark theme");
      toggle.setAttribute("aria-pressed", String(isDark));
    }
    toggle.addEventListener("click", function () {
      var next = resolvedTheme() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      var meta = document.querySelector('meta[name="color-scheme"]');
      if (meta) meta.content = next;
      try { localStorage.setItem("cperch-theme", next); } catch (e) {}
      syncLabel();
    });
    syncLabel();
  }

  // Copy buttons: <button class="copy" data-copy-target="#id">
  document.querySelectorAll(".copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var sel = btn.getAttribute("data-copy-target");
      var src = sel && document.querySelector(sel);
      if (!src) return;
      // Use the data-copy attribute if present (clean commands), else the text content.
      var text = src.getAttribute("data-copy") || src.textContent;
      navigator.clipboard.writeText(text.trim()).then(function () {
        var label = btn.querySelector(".copy-label");
        if (!label) return;
        var prev = label.textContent;
        label.textContent = "Copied";
        setTimeout(function () { label.textContent = prev; }, 1600);
      }).catch(function () {});
    });
  });
})();
