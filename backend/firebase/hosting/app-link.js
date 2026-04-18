(function () {
    const APP_STORE_URL = "https://apps.apple.com/ca/app/meerkat-milage-tracker/id6760921171";
    const APP_SCHEME_URL = "meerkat-mileage-tracker://";

    function isMobileDevice() {
        return /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
    }

    function openAppWithFallback() {
        const start = Date.now();
        window.location.href = APP_SCHEME_URL;

        window.setTimeout(function () {
            const elapsed = Date.now() - start;
            if (elapsed < 1800) {
                window.location.href = APP_STORE_URL;
            }
        }, 1200);
    }

    function openStore() {
        window.location.href = APP_STORE_URL;
    }

    const openAppButton = document.getElementById("open-app");
    const appStoreButton = document.getElementById("open-store");

    if (openAppButton) {
        openAppButton.addEventListener("click", openAppWithFallback);
    }

    if (appStoreButton) {
        appStoreButton.addEventListener("click", openStore);
    }

    const params = new URLSearchParams(window.location.search);
    if (params.get("autostart") === "1" && isMobileDevice()) {
        openAppWithFallback();
    }
})();
