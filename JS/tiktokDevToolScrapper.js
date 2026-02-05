const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function scrollDown() {
    const originalHeight = document.body.scrollHeight;
    window.scrollTo(0, document.body.scrollHeight);
    return originalHeight;
}

async function awaitAndIncreaseTime(waitTime) {
    await sleep(waitTime);
    return waitTime;
}

/**
 * Scrapes a page by scrolling to the bottom, then executing a callback.
 * @param {Function} fn - The function to execute after scrolling (or during).
 * @param {string|null} where - Control flag. Pass "EVERYLOOP" to run fn on every scroll (rare), or null to run at the end.
 */
async function scrapeTikTokMedia(fn, where = null) {
    if (fn && typeof fn !== "function") {
        throw Error("The argument passed is not a function.");
    }

    const validWheres = [null, "EVERYLOOP"];
    if (!validWheres.includes(where)) {
        throw Error("No valid 'where' argument.");
    }

    console.log("Starting Scroller...");
    const TIMEOUT = 10000;
    const MAX_RETRIES = 3;
    while (true) {
        let previousHeight = scrollDown();

        // Wait for height change
        let heightChanged = false;
        let waittime = 0;
        const checkInterval = 500;
        let currentRetry = 0;
        while (waittime < TIMEOUT) {
            waittime += await awaitAndIncreaseTime(checkInterval);

            if (document.body.scrollHeight > previousHeight) {
                heightChanged = true;
                break;
            }

            if (currentRetry < MAX_RETRIES) {
                waittime += await awaitAndIncreaseTime(checkInterval);
                previousHeight = scrollDown();
                currentRetry += 1;
            }
        }

        if (!heightChanged) {
            console.log("Reached bottom or timed out.");
            break;
        }

        await sleep(1000); // Let UI settle

        if (where === "EVERYLOOP" && fn) {
            //console.log("Executing callback for this loop...");
            await fn();
        }
    }

    // 3. Fixed Logic: Execute fn at the end
    if (!where && fn) {
        //console.log("Scrolling finished. Executing extraction...");
        await fn();
    }
}

function getTiktokVideos() {
    let getTikTokUsername = (url) => {
        try {
            const parts = url.split("/");
            const domainIndex = parts.findIndex((p) => p.includes("tiktok.com"));
            const usernamePart = parts[domainIndex + 1];
            return usernamePart.startsWith("@") ? usernamePart.slice(1) : "";
        } catch (errorMessage) {
            logger.error(`Function getTikTokUsername Failed: ${errorMessage}`);
            return "";
        }
    };
    //Get username variables
    const userDictionary = {};
    let currentUsername = "NO_USER_GIVEN";
    let userDictionaryMaxCount = -1;

    //DateVariable
    const currentDate = new Date();
    const year = currentDate.getFullYear();
    const month = (currentDate.getMonth() + 1).toString().padStart(2, "0"); // Pad with leading zero if needed
    const day = currentDate.getDate().toString().padStart(2, "0"); // Pad with leading zero if needed

    const customFormattedDate = `${year}_${month}_${day}`;

    //Links variables
    const listVideo = document.querySelectorAll("a");
    const arrayOfTiktokMedia = Array.from(listVideo).map((item) => item.href);
    const videoURLs1 = arrayOfTiktokMedia.filter((href) => href.includes("/video/")).filter((value, index, self) => self.indexOf(value) === index);
    const imagesURLs1 = arrayOfTiktokMedia.filter((href) => href.includes("/photo/")).filter((value, index, self) => self.indexOf(value) === index);
    const urls = videoURLs1.concat(imagesURLs1);

    for (const url of urls) {
        let tmpUser = getTikTokUsername(url) || currentUsername;
        userDictionary[tmpUser] = (userDictionary[tmpUser] ?? 0) + 1;
        if (userDictionary[tmpUser] > userDictionaryMaxCount) {
            currentUsername = tmpUser;
            userDictionaryMaxCount = userDictionary[tmpUser];
        }
    }
    //Result should only have urls that contain currentUsername
    result = urls.filter((url) => getTikTokUsername(url) === currentUsername);
    const dataToDownload = result.join("\n");

    // Create a Blob with MIME type for plain text
    const blob = new Blob([dataToDownload], { type: "text/plain" });

    // Create and configure the download link
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${currentUsername}_${customFormattedDate}_TiktokData.txt`;
    document.body.appendChild(a);
    a.click();

    // Clean up
    document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
}

await scrapeTikTokMedia(getTiktokVideos);
