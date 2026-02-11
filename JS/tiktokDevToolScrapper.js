"use strict";
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function scrollDown() {
    const originalHeight = document.body.scrollHeight;
    window.scrollTo(0, document.body.scrollHeight);
    return originalHeight;
}

async function awaitAndIncreaseTime(waitTime) {
    const start = Date.now();
    await sleep(waitTime);
    const end = Date.now();
    const actualDuration = end - start;

    if (actualDuration > waitTime + 200) {
        console.warn(`Throttling detected: Asked for ${waitTime}ms, but waited ${actualDuration}ms.`);
    }
    return waitTime;
}

/**
 * Scrapes a page by scrolling to the bottom, then executing a callback.
 */
async function scrapeTikTokMedia(fn, where = null) {
    if (fn && typeof fn !== "function") throw Error("Argument is not a function.");
    if (![null, "EVERYLOOP"].includes(where)) throw Error("Invalid 'where' argument.");

    console.log("Starting Scroller...");
    const TIMEOUT = 10000;
    const MAX_RETRIES = 3;
    const CHECK_INTERVAL = 500;

    // Safety break to prevent browser crash on massive profiles
    const MAX_LOOPS = 2000;
    let loopCount = 0;

    while (loopCount < MAX_LOOPS) {
        loopCount++;
        let previousHeight = scrollDown();
        let heightChanged = false;
        let waitTimeAccumulated = 0;
        let currentRetry = 0;

        // Wait loop: checks every 500ms if height changed
        while (waitTimeAccumulated < TIMEOUT) {
            waitTimeAccumulated += await awaitAndIncreaseTime(CHECK_INTERVAL);

            if (document.body.scrollHeight > previousHeight) {
                heightChanged = true;
                break;
            }

            // Retry scroll if stuck (lazy load glitches)
            if (currentRetry < MAX_RETRIES) {
                console.log(`Retry scroll ${currentRetry + 1}/${MAX_RETRIES}`);
                previousHeight = scrollDown();
                currentRetry++;
            }
        }

        if (!heightChanged) {
            console.log("Reached bottom or timed out.");
            break;
        }

        await sleep(1000); // Let UI settle

        if (where === "EVERYLOOP" && fn) {
            await fn();
        }
    }

    if (!where && fn) {
        console.log("Scrolling finished. Executing extraction...");
        await fn();
    }
}

function getTiktokVideos() {
    const getTikTokUsername = (url) => {
        try {
            const parts = url.split("/");
            // Handle both desktop and mobile URL structures roughly
            const domainIndex = parts.findIndex((p) => p.includes("tiktok.com"));
            if (domainIndex === -1 || !parts[domainIndex + 1]) return "";

            const usernamePart = parts[domainIndex + 1];
            // Remove query params if any exist (e.g. @user?lang=en)
            const cleanUser = usernamePart.split("?")[0];
            return cleanUser.startsWith("@") ? cleanUser.slice(1) : "";
        } catch (errorMessage) {
            console.error(`Function getTikTokUsername Failed: ${errorMessage}`);
            return "";
        }
    };

    // --- Data Collection ---
    const userDictionary = {};
    let currentUsername = "NO_USER_GIVEN";
    let userDictionaryMaxCount = -1;

    // 1. Grab all links
    const listVideo = document.querySelectorAll("a");
    // 2. Convert to href strings
    const arrayOfTiktokMedia = Array.from(listVideo).map((item) => item.href);

    // 3. Filter and Deduplicate using Set (O(N) instead of O(N^2))
    const videoSet = new Set(arrayOfTiktokMedia.filter((href) => href.includes("/video/")));
    const photoSet = new Set(arrayOfTiktokMedia.filter((href) => href.includes("/photo/")));

    // Merge sets back to array
    const urls = [...videoSet, ...photoSet];

    // 4. Identify most frequent username
    for (const url of urls) {
        let tmpUser = getTikTokUsername(url) || currentUsername;
        if (tmpUser === "NO_USER_GIVEN") continue;

        userDictionary[tmpUser] = (userDictionary[tmpUser] ?? 0) + 1;
        if (userDictionary[tmpUser] > userDictionaryMaxCount) {
            currentUsername = tmpUser;
            userDictionaryMaxCount = userDictionary[tmpUser];
        }
    }

    console.log(`Detected Username: ${currentUsername} with ${urls.length} potential items found.`);

    // 5. Final Filter
    const result = urls.filter((url) => getTikTokUsername(url) === currentUsername);
    const dataToDownload = result.join("\n");

    // --- File Download ---
    const currentDate = new Date();
    const year = currentDate.getFullYear();
    const month = (currentDate.getMonth() + 1).toString().padStart(2, "0");
    const day = currentDate.getDate().toString().padStart(2, "0");
    const customFormattedDate = `${year}_${month}_${day}`;

    const blob = new Blob([dataToDownload], { type: "text/plain" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${currentUsername}_${customFormattedDate}_TiktokData.txt`;
    document.body.appendChild(a);
    a.click();

    document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
}

// Execute
await scrapeTikTokMedia(getTiktokVideos);
