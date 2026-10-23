Build a complete, production-ready macOS Menu Bar application in Swift (macOS 14.0+, SwiftUI) called **opaq**. Use Swift Package Manager (`Package.swift`) with an executable target named `opaq`, and include a `build_app.sh` packaging script that compiles the binary, creates a proper `opaq.app` bundle with an `Info.plist`, and ad-hoc code signs it so macOS TCC permissions (Contacts & Full Disk Access) persist cleanly across runs. Do not use any third-party dependencies; use the built-in macOS `SQLite3` C API, `Contacts`, `AppKit`, and `SwiftUI`.

## 1. Core Purpose & Behavior
**opaq** monitors the local macOS iMessage database (`~/Library/Messages/chat.db`) in strictly READ-ONLY mode to prevent me from accidentally ghosting specific people I add to my tracked list.

- **Menu Bar Agent Only (No Dock Icon):** Configure the app as an agent (`LSUIElement = true` in `Info.plist` and `NSApp.setActivationPolicy(.accessory)` on launch) so it lives exclusively in the macOS top menu bar, with a standalone Settings window that opens on demand.
- **Permissions Onboarding:** Gracefully check for both **Contacts Access** (`CNContactStore.authorizationStatus(for: .contacts)`) and **Full Disk Access** (by attempting to open `~/Library/Messages/chat.db` in read-only mode). If either permission is missing or denied, show an onboarding card in both the dropdown and Settings window with direct action buttons to open:
  - Full Disk Access: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
  - Contacts Access: `x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts`
  - Plus a **"Retry Connection"** button.

---

## 2. Contact Resolution & Multi-Handle Grouping (`ContactManager.swift`)
In iMessage, a single person often texts from multiple handles (e.g., `+15551234567` and `alex@icloud.com`).
1. Fetch all contacts from `CNContactStore` requesting `CNContactIdentifierKey`, `CNContactGivenNameKey`, `CNContactFamilyNameKey`, `CNContactThumbnailImageDataKey`, `CNContactPhoneNumbersKey`, and `CNContactEmailAddressesKey`.
2. Normalize all phone numbers and emails:
   - For phone numbers: strip all non-digit characters (except leading `+`). Match both exact normalized strings and the last 10 digits so local numbers match E.164 (`+1XXXXXXXXXX`) handles in `chat.db`.
   - For emails: trim whitespace and lowercase.
3. Define the `TrackedPerson` model (`Codable`, `Identifiable`, `Equatable`):
   - `id: String` (`CNContact.identifier`, or the normalized handle if added manually without a contact card)
   - `displayName: String`
   - `handles: [String]` (all raw handle strings from `chat.db` and `CNContact` associated with this person)
   - `avatarData: Data?` (loaded dynamically from `CNContact` by `id`)

---

## 3. SQLite Queries & Ghosting Logic (`DatabaseService.swift`)
Always open `~/Library/Messages/chat.db` using `sqlite3_open_v2` with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` (or URI `file:///Users/<user>/Library/Messages/chat.db?mode=ro`). **Never** write to or lock `chat.db`.

- **Apple CoreData Timestamps:** `m.date` in `chat.db` is nanoseconds since `2001-01-01 00:00:00 UTC`. Convert to Unix epoch seconds via `(m.date / 1000000000) + 978307200`.

### Query A: Time-Decayed Suggestions (for the "Add People" Modal/Settings)
Suggest untracked people from 1-on-1 chats (`c.style = 45`) ranked by message volume weighted by recency using an exponential time-decay formula:

```sql
SELECT 
    h.id AS handle_identifier,
    COUNT(m.ROWID) AS total_messages,
    SUM(
        1.0 / (1.0 + ((strftime('%s', 'now') - (m.date / 1000000000 + 978307200)) / 86400.0) * 0.1)
    ) AS recency_weighted_score
FROM message m
JOIN handle h ON m.handle_id = h.ROWID
JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
JOIN chat c ON cmj.chat_id = c.ROWID
WHERE c.style = 45 
GROUP BY h.id
ORDER BY recency_weighted_score DESC
LIMIT 100;
```

In Swift:
1. Map each returned `handle_identifier` to a `CNContact` (if available).
2. Group handles belonging to the same `CNContact.identifier` so one person only appears once in the suggestion list, summing their `total_messages` and `recency_weighted_score`, and combining their `handles`.
3. Filter out anyone already in `trackedPeople`.

### Query B: Unreplied Status Across Tracked People
For each `TrackedPerson`, check all messages across **all** of their matched `handles` in 1-on-1 chats (`c.style = 45`) and find the single most recent valid interaction:
- **My Reactions Count as Replies:** In `chat.db`, Tapback reactions are rows with `associated_message_type BETWEEN 2000 AND 2005`. Keep rows where `m.is_from_me = 1` and `m.associated_message_type BETWEEN 2000 AND 2005`. If the latest event in the thread is my reaction, `is_from_me == 1`, meaning I have responded.
- **Ignore Their Reactions:** Exclude rows where `m.is_from_me = 0 AND m.associated_message_type BETWEEN 2000 AND 2005` so that when someone reacts to *my* message (e.g., likes my text), it does NOT mark me as ghosting them.
- **Ignore Reaction Removals & System Events:** Filter `m.item_type = 0` and `m.associated_message_type NOT BETWEEN 3000 AND 3005`.

```sql
SELECT 
    c.chat_identifier,
    m.ROWID AS message_id,
    m.is_from_me,
    m.date AS raw_apple_date,
    (m.date / 1000000000 + 978307200) AS unix_timestamp
FROM chat c
JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
JOIN message m ON cmj.message_id = m.ROWID
WHERE c.style = 45
  AND c.chat_identifier IN (<BOUND_HANDLES_FOR_PERSON>)
  AND m.item_type = 0
  AND m.associated_message_type NOT BETWEEN 3000 AND 3005
  AND NOT (m.is_from_me = 0 AND m.associated_message_type BETWEEN 2000 AND 2005)
ORDER BY m.date DESC
LIMIT 1;
```

---

## 4. State Rules: "Conversation Ended", Grace Period & Quiet Hours (`OpaqViewModel.swift`)
Persist all user configuration in `UserDefaults` using `Codable` structs.

1. **"Conversation Ended" Button Logic:**
   - Maintain `dismissedTimestamps: [String: Int64]` mapping `TrackedPerson.id -> raw_apple_date`.
   - When the user clicks the **"Conversation Ended"** button for a person in the dropdown, set `dismissedTimestamps[person.id] = latestMessage.raw_apple_date`.
   - A person is only considered **Unreplied** if `latestMessage.is_from_me == 0` AND `latestMessage.raw_apple_date > (dismissedTimestamps[person.id] ?? 0)`.
   - When that person sends a newer message in the future, its `raw_apple_date` will automatically exceed the stored timestamp and they will reappear in the unreplied list.

2. **Ranking Order:**
   - All currently unreplied tracked people must be sorted in ascending order of `unix_timestamp` (i.e., **longest time since their last message is #1 at the top**).

3. **Grace Period Threshold:**
   - Configurable in Settings (Slider from `0` to `24` hours, default `2.0` hours).
   - If a person's wait time (`now - unix_timestamp`) is less than `gracePeriodHours`, they still appear at the bottom of the dropdown under a muted `"Recent (In Grace Period)"` section, but they **do not** trigger the top Menu Bar timer text until their wait time exceeds the Grace Period.

4. **Weekly "Quiet Hours" Schedule (Suppresses Menu Bar Timer Only):**
   - Allow the user to configure recurring weekly windows when they are not expected to reply (default: Monday through Friday, `09:00` to `17:00`).
   - Model as `QuietHoursSchedule`:
     - `isEnabled: Bool` (default `true`)
     - `activeWeekdays: Set<Int>` (Calendar weekday `1...7`, default Mon–Fri `2,3,4,5,6`)
     - `startHour: Int`, `startMinute: Int` (default `9:00`)
     - `endHour: Int`, `endMinute: Int` (default `17:00`)
   - **Rule during Quiet Hours:** When the current local time falls inside an enabled Quiet Hours window:
     - The **Menu Bar icon MUST show ONLY the cute ghost icon** (never replace or append the timer text during Quiet Hours).
     - As soon as Quiet Hours end (e.g., after 5:00 PM), the Menu Bar immediately switches to showing the longest unreplied duration (if any tracked person is past the grace period).
     - The **Dropdown UI MUST still show the full ranked list** of unreplied people at all times, along with a subtle status banner at the top when Quiet Hours are active (e.g., `"Quiet Hours active until 5:00 PM — Menu bar timer paused"`).

---

## 5. Real-Time Monitoring (`FileWatcher.swift`)
1. Monitor `~/Library/Messages/chat.db-wal` (and fallback to `~/Library/Messages/chat.db`) using `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:[.write, .extend, .attrib, .rename], queue:)`.
2. Debounce file events by `400ms` so incoming message bursts trigger a single read query.
3. Run a 30-second repeating `Timer` on the main actor to update formatted relative duration strings (`4d 2h`, `6h 15m`, `45m`) and immediately transition the menu bar icon when Quiet Hours start/end or when a conversation crosses the Grace Period.

---

## 6. User Interface Specifications

### A. Top Menu Bar Icon (`MenuBarExtra`)
- Use `.menuBarExtraStyle(.window)`.
- Create a dedicated `GhostIconView` / `NSImage` generator that draws a crisp, cute minimalist ghost silhouette (template image so it adapts to Light/Dark menu bars) with two eyes and a wavy bottom.
- **Display Logic:**
  - If `isQuietHoursActive == true` OR `unrepliedPastGracePeriod.isEmpty`: show **only** the cute ghost icon.
  - Otherwise: show the cute ghost icon + the **maximum** unreplied duration from `unrepliedPastGracePeriod.first` (e.g., `👻 3d 14h` or `👻 5h 20m` using `.monospacedDigit()`).

### B. Menu Bar Dropdown Window (`DropdownView.swift`, width: `360`)
- **Top Header Bar:**
  - Left: App title `"opaq"` and count badge.
  - Right: Refresh button and Settings button (gear icon) that opens and focuses the main Settings window (`NSApp.activate(ignoringOtherApps: true)`).
- **Quiet Hours Banner (Conditional):**
  - Shown when currently inside Quiet Hours: `"🌙 Quiet Hours (9:00 AM – 5:00 PM) • Timer hidden"`.
- **Unreplied List (Ordered Longest Waiting First):**
  - If empty: Display a happy ghost illustration and `"You're all caught up! No one is being ghosted."`
  - For each unreplied person row:
    - **Avatar / Initials Circle** + **Contact Name**.
    - **Color-Coded Urgency Badge** showing time since their last message:
      - `< 24 hours`: Neutral Secondary/Gray badge
      - `24 – 72 hours (1–3 days)`: Yellow/Amber badge
      - `> 72 hours (3+ days)`: Red/Coral badge
    - **Primary Click Action (Deep Link to iMessage):** Clicking the person's name/info opens the macOS Messages app directly to their thread using `NSWorkspace.shared.open(URL(string: "imessage://\(primaryHandle)")!)`.
    - **"Conversation Ended" Button:** A dedicated checkmark button on the right side of the row (`checkmark.circle` / `"Ended"`) with a hover tooltip `"Conversation ended naturally (don't count as ghosting)"`.

### C. Main Settings Window (`SettingsWindowView.swift`, size: `680x520`)
Provide a clean 3-tab Settings window titled `"opaq Settings"`:
1. **Tab 1: Tracked People (`PeopleManagerView`)**
   - Split or two-section layout:
     - **Currently Tracked List:** Shows all tracked people, their linked handles, and a `"Remove"` button.
     - **Smart Suggestions ("Who You Text Most & Recently"):** Powered by Query A. Displays suggested contacts ranked by the recency-weighted frequency score, showing a badge with total message count and a `+ Track` button. Include a search bar at the top that searches both suggestions and your full `CNContactStore` so you can add anyone manually.
2. **Tab 2: Quiet Hours (`QuietHoursView`)**
   - Master toggle: `"Pause Menu Bar Timer During Quiet Hours"`.
   - Interactive day-of-week selector buttons (`Sun`, `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`).
   - Start Time and End Time pickers (default `9:00 AM` to `5:00 PM`).
   - Live indicator showing whether Quiet Hours are *currently active* right now.
3. **Tab 3: Rules & Permissions (`PreferencesView`)**
   - **Grace Period Slider:** `0` to `24` hours (step `0.5` hours) explaining: *"Wait this long after receiving a message before showing the timer in the menu bar."*
   - **Permissions Status Card:** Live green/red status indicators for **Full Disk Access (`chat.db`)** and **Contacts Access**, with quick-open System Settings buttons.

---

## 7. Build, Bundle & Verification Steps
1. Create the full project structure with `Package.swift` and all Swift files inside `Sources/opaq/`.
2. Create an executable `build_app.sh` script in the root directory that:
   - Runs `swift build -c release`
   - Creates `opaq.app/Contents/MacOS` and `opaq.app/Contents/Resources`
   - Writes a valid `opaq.app/Contents/Info.plist` with `CFBundleName` (`opaq`), `CFBundleDisplayName` (`opaq`), `CFBundleIdentifier` (`com.local.opaq`), `LSUIElement = true`, and `NSContactsUsageDescription`.
   - Copies the compiled binary into `opaq.app/Contents/MacOS/opaq`
   - Runs `codesign --force --deep --sign - opaq.app`
3. Run `chmod +x build_app.sh && ./build_app.sh` and fix any compilation errors or warnings until `opaq.app` builds cleanly with zero errors.