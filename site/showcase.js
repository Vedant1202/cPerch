// cPerch site — feature showcase carousel.
// CSS scroll-snap does the layout; this adds dots, arrows, keyboard, and a
// gentle autoplay that pauses on hover/focus, when the tab is hidden, and
// whenever the visitor prefers reduced motion.

(function () {
  "use strict";

  var carousel = document.querySelector(".carousel");
  if (!carousel) return;

  var track = carousel.querySelector(".track");
  var slides = Array.prototype.slice.call(track.querySelectorAll(".slide"));
  var dots = Array.prototype.slice.call(carousel.querySelectorAll(".dot"));
  var prev = carousel.querySelector(".car-arrow.prev");
  var next = carousel.querySelector(".car-arrow.next");
  var playBtn = carousel.querySelector(".car-play");
  if (slides.length < 2) return;

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var AUTOPLAY_MS = 5200;
  var current = 0;
  var timer = null;
  var userPaused = reduce.matches; // no autoplay under reduced motion

  function scrollToIndex(i, smooth) {
    var left = i * track.clientWidth;
    if (smooth && !reduce.matches) track.scrollTo({ left: left, behavior: "smooth" });
    else track.scrollLeft = left;
  }

  function setCurrent(i) {
    current = i;
    for (var d = 0; d < dots.length; d++) {
      if (d === i) dots[d].setAttribute("aria-current", "true");
      else dots[d].removeAttribute("aria-current");
    }
  }

  function go(i, smooth) {
    var n = slides.length;
    i = ((i % n) + n) % n; // wrap around
    setCurrent(i);
    scrollToIndex(i, smooth !== false);
  }

  // Keep the dots in sync with whatever slide is actually centered, including
  // manual swipes/scrolls.
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && e.intersectionRatio >= 0.6) {
          var idx = slides.indexOf(e.target);
          if (idx !== -1) current = idx, syncDots(idx);
        }
      });
    }, { root: track, threshold: [0.6] });
    slides.forEach(function (s) { io.observe(s); });
  }
  function syncDots(i) {
    for (var d = 0; d < dots.length; d++) dots[d].toggleAttribute("aria-current", d === i);
  }

  // --- autoplay ---
  function clearTimer() { if (timer) { clearInterval(timer); timer = null; } }
  function armTimer() {
    clearTimer();
    if (!userPaused && !reduce.matches) timer = setInterval(function () { go(current + 1); }, AUTOPLAY_MS);
  }
  function syncPlayUI() {
    if (!playBtn) return;
    var playing = !userPaused;
    playBtn.classList.toggle("paused", !playing);
    playBtn.setAttribute("aria-pressed", String(playing));
    playBtn.setAttribute("aria-label", playing ? "Pause the feature tour" : "Play the feature tour");
  }

  // --- controls ---
  if (prev) prev.addEventListener("click", function () { go(current - 1); armTimer(); });
  if (next) next.addEventListener("click", function () { go(current + 1); armTimer(); });
  dots.forEach(function (dot, di) { dot.addEventListener("click", function () { go(di); armTimer(); }); });

  track.addEventListener("keydown", function (e) {
    if (e.key === "ArrowLeft") { e.preventDefault(); go(current - 1); armTimer(); }
    else if (e.key === "ArrowRight") { e.preventDefault(); go(current + 1); armTimer(); }
  });

  if (playBtn) {
    playBtn.addEventListener("click", function () { userPaused = !userPaused; syncPlayUI(); armTimer(); });
  }

  // pause while the visitor is engaging or away; resume otherwise
  carousel.addEventListener("mouseenter", clearTimer);
  carousel.addEventListener("mouseleave", armTimer);
  carousel.addEventListener("focusin", clearTimer);
  carousel.addEventListener("focusout", armTimer);
  track.addEventListener("touchstart", clearTimer, { passive: true });
  track.addEventListener("touchend", armTimer, { passive: true });
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) clearTimer(); else armTimer();
  });

  if (reduce.addEventListener) {
    reduce.addEventListener("change", function () {
      if (reduce.matches) { userPaused = true; clearTimer(); }
      syncPlayUI();
    });
  }

  // init
  setCurrent(0);
  if (reduce.matches && playBtn) playBtn.hidden = true; // no autoplay to control
  syncPlayUI();
  armTimer();
})();
