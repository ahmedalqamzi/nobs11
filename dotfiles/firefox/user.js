// Low-memory fallback profile. Keep site isolation, the sandbox, GPU
// acceleration, Safe Browsing, and automatic security updates enabled.
user_pref("dom.ipc.processCount", 4);
user_pref("dom.ipc.processCount.webIsolated", 4);
user_pref("dom.ipc.keepProcessesAlive.webIsolated", 1);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.sessionhistory.max_total_viewers", 2);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("browser.newtab.preload", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
