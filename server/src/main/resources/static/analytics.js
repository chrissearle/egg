/*
 * Loads the site's Umami tracker, and gives the game a way to report events.
 *
 * Included by every server-rendered page (Site.kt) and by the game page (the
 * export preset's `html/head_include`). The settings come from /api/analytics,
 * which answers only when the deployment configures them: run anywhere else,
 * or on a host not in the configured domains, and nothing is fetched from
 * Umami at all.
 *
 * window.eggTrack(name, data) is what the game calls through JavaScriptBridge.
 * Events sent before the tracker has loaded are held and replayed, so a game
 * started quickly still counts; once it is clear there will be no tracker they
 * are dropped.
 */
(function () {
  "use strict";

  var MAX_QUEUED = 50;
  var queue = [];

  window.eggTrack = function (name, data) {
    if (window.umami && typeof window.umami.track === "function") {
      window.umami.track(name, data);
    } else if (queue && queue.length < MAX_QUEUED) {
      queue.push([name, data]);
    }
  };

  function giveUp() {
    queue = null;
  }

  function load(settings) {
    if (!settings || settings.domains.indexOf(window.location.hostname) === -1) {
      giveUp();
      return;
    }

    var tag = document.createElement("script");
    tag.defer = true;
    tag.src = settings.src;
    tag.setAttribute("data-website-id", settings.websiteId);
    tag.setAttribute("data-domains", settings.domains.join(","));
    tag.onload = function () {
      var held = queue || [];
      queue = null;
      held.forEach(function (event) {
        window.umami.track(event[0], event[1]);
      });
    };
    tag.onerror = giveUp;
    document.head.appendChild(tag);
  }

  fetch("/api/analytics", { credentials: "same-origin" })
    .then(function (response) {
      return response.status === 200 ? response.json() : null;
    })
    .then(load)
    .catch(giveUp);
})();
