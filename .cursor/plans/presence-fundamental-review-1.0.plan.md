---
name: ""
overview: ""
todos: []
isProject: false
---

# Presence Module — Fundamental Review for 1.0

Combined plan: colour/text robustness, **systems shown / how they show**, **edge cases**, and **visual UX consistency**.

---

## Part 1: Colour & Live Text (existing review)

### Current architecture

- **resolveColors(typeName, cfg, opts)** in [PresenceCore.lua](modules/Presence/PresenceCore.lua) is the only place that turns type/options into RGB. Called **once per notification** from `PlayCinematic`, not on every frame.
- **PlayCinematic** applies the result to the active layer; no colour work in animation phases. **PresenceOnUpdate** only changes alpha and layout; runs only while `anim.phase ~= "idle"` and is cleared in `onComplete` / `HideAndClear`. **No per-frame colour or text logic.**

### Colour sources


| Source                            | Used in Presence                    | When read                    |
| --------------------------------- | ----------------------------------- | ---------------------------- |
| `addon.GetQuestColor(cat)`        | resolveColors (title/sub)           | Each PlayCinematic           |
| `addon.QUEST_COLORS[cat]`         | resolveColors fallback; CreateLayer | PlayCinematic + once at Init |
| `addon.PRESENCE_BOSS_EMOTE_COLOR` | resolveColors (BOSS_EMOTE)          | Each PlayCinematic           |
| `addon.PRESENCE_DISCOVERY_COLOR`  | CreateLayer only                    | Once at Init                 |
| `addon.SHADOW_A`                  | CreateLayer (shadow alpha)          | Once at Init                 |


### Issues and recommendations (colour)

1. **Discovery line colour baked at init** — Resolve at show time: add `getDiscoveryColor()` (or shared `getCategoryColor`) and set discovery text colour when setting "Discovered" in PlayCinematic and in ShowDiscoveryLine().
2. **Optional:** Centralise category colour in a small `getCategoryColor(cat, default)` used by resolveColors and discovery; set subText/discoveryText in CreateLayer to a neutral default so options changes can apply without recreating layers.
3. **Document** — Comment that colour is resolved only at show time and OnUpdate does not touch colour or text.

---

## Part 2: Systems Shown & How They Show

### Notification types (TYPES in PresenceCore.lua)


| Type               | Priority | Trigger (Events)                                           | Title (typical)        | Subtitle (typical)             | Title sz | Hold dur |
| ------------------ | -------- | ---------------------------------------------------------- | ---------------------- | ------------------------------ | -------- | -------- |
| LEVEL_UP           | 4        | PLAYER_LEVEL_UP                                            | "LEVEL UP"             | "You have reached level N"     | 48       | 5.0      |
| BOSS_EMOTE         | 4        | RAID_BOSS_EMOTE                                            | Boss name              | Emote text (no icons, %s→name) | 48       | 5.0      |
| ACHIEVEMENT        | 3        | ACHIEVEMENT_EARNED                                         | "ACHIEVEMENT EARNED"   | Achievement name               | 48       | 4.5      |
| QUEST_COMPLETE     | 2        | QUEST_TURNED_IN                                            | "QUEST COMPLETE"       | Quest title                    | 48       | 4.0      |
| WORLD_QUEST        | 2        | QUEST_TURNED_IN (WQ)                                       | "WORLD QUEST"          | Quest title                    | 48       | 4.0      |
| ZONE_CHANGE        | 2        | ZONE_CHANGED_NEW_AREA (deferred)                           | Zone name              | Subzone                        | 48       | 4.0      |
| QUEST_ACCEPT       | 1        | QUEST_ACCEPTED                                             | "QUEST ACCEPTED"       | Quest title                    | 36       | 3.0      |
| WORLD_QUEST_ACCEPT | 1        | QUEST_ACCEPTED (WQ)                                        | "WORLD QUEST ACCEPTED" | Quest title                    | 36       | 3.0      |
| QUEST_UPDATE       | 1        | QUEST_WATCH_UPDATE, QUEST_LOG_UPDATE (WQ), UI_INFO_MESSAGE | "QUEST UPDATE"         | Objective text                 | 20       | 2.5      |
| SUBZONE_CHANGE     | 1        | ZONE_CHANGED / ZONE_CHANGED_INDOORS                        | Zone name              | Subzone                        | 36       | 3.0      |


### How each is shown

- **Single frame**, two layers (A/B) for crossfade when a higher-priority notification interrupts.
- **Layout:** Title (with optional quest-type icon) → divider → subtitle → discovery line ("Discovered" for zone/subzone when applicable).
- **Animation:** Entrance (staggered: title → divider → subtitle → discovery) over ENTRANCE_DUR 0.7s; hold; exit over EXIT_DUR 0.8s. If something is already visible and a higher-or-equal priority comes in, crossfade: old layer fades out over CROSSFADE_DUR 0.4s while new layer runs full entrance (0.7s).
- **Quest-type icon:** Shown for quest-related types when `opts.questID` is set and `showQuestTypeIcons` is on; atlas from `addon.GetQuestTypeAtlas(opts.questID, catForAtlas)`. Icon size matches title (capped by QUEST_ICON_SIZE 24).
- **Zone/subzone special behaviour:** If the current toast is already showing the same zone (activeTitle == zone) and phase is hold or entrance, zone events call **SoftUpdateSubtitle(sub)** and optionally **ShowDiscoveryLine()** instead of queuing a new ZONE_CHANGE/SUBZONE_CHANGE. "Discovered" is set when UIErrorsFrame reports "Discovered" (PresenceErrors) or when pendingDiscovery was set and we show a zone toast.

### Data flow (high level)

- Events (PresenceEvents) → QueueOrPlay(typeName, title, subtitle, opts).
- QueueOrPlay: combat filter (pri &lt; 4 suppressed in combat), then either interrupt current and PlayCinematic, or queue (up to MAX_QUEUE 5), or play if idle.
- PlayCinematic: resolveColors, set fonts/sizes/colors/text/icon, resetLayer (alpha 0), set discovery text if pending, then start entrance or crossfade and attach OnUpdate.
- OnUpdate drives entrance → hold → exit; on completion, clears frame and optionally plays next from queue (by highest priority).

---

## Part 3: Edge Cases & Issues

### Combat

- **InCombatLockdown() and cfg.pri &lt; 4:** All but LEVEL_UP and BOSS_EMOTE are suppressed. No feedback to the user; notification is dropped (and not queued). **Consider:** Option to queue and show after combat, or at least document behaviour.

### Queue

- **MAX_QUEUE = 5.** When queue is full, lower-priority items are dropped (no feedback). After completion, next is chosen by **highest priority** only (first of that priority in queue), not FIFO within same priority. **Edge:** Several same-priority items can reorder by insertion order when multiple are in queue.

### Zone / subzone ordering

- **ZONE_CHANGED_NEW_AREA** vs **ZONE_CHANGED** / **ZONE_CHANGED_INDOORS:** Order can vary (e.g. indoors vs new area). Both use DISCOVERY_WAIT (0.15s) and a deferred callback. If subzone event runs first, we may show SUBZONE_CHANGE(zone, sub) before ever showing ZONE_CHANGE(zone, sub). **Consider:** Coalesce zone+subzone within a short window so we always show one zone toast with final subzone, or document that subzone-only can appear first.

### Discovery timing

- **SetPendingDiscovery()** is called from UIErrorsFrame when message contains "Discovered". If the zone toast is already on screen (same zone, hold/entrance), we ShowDiscoveryLine() and clear pending. If not, pendingDiscovery is set and the next ZONE_CHANGE/SUBZONE_CHANGE in PlayCinematic sets "Discovered" on the layer. **Edge:** If "Discovered" fires after the zone toast has already been replaced by another type, we never show "Discovered". Acceptable for 1.0; document.

### Quest update double-source

- **QUEST_WATCH_UPDATE** (tracked quests) and **UI_INFO_MESSAGE** (IsQuestText) can both fire for similar progress. **QUEST_LOG_UPDATE** (debounced 0.2s) is used for world-quest super-tracked only. Throttle per quest (1.5s) in TryShowQuestUpdate reduces spam. **Edge:** Same objective update could in theory come from both UI_INFO_MESSAGE and QUEST_WATCH_UPDATE; throttle minimises duplicates.

### Quest accept / turn-in

- **C_QuestLog.GetTitleForQuestID(questID)** can be nil at accept/turn-in. Fallbacks: "New Quest", "Objective". **GetAchievementInfo(achID)** can return nil name; we use name or "".

### Crossfade phase duration

- Crossfade phase runs for **ENTRANCE_DUR** (0.7s); old layer fade uses **CROSSFADE_DUR** (0.4s). So after 0.4s the old layer is fully faded; 0.4–0.7s is just new layer entrance. Behaviour is consistent and intentional.

### ShowDiscoveryLine during phase

- If we call ShowDiscoveryLine() during **entrance**, we only set text; alpha is driven by updateEntrance (DELAY_DISCOVERY), so discovery line animates in. If during **hold**, we set alpha to 1/0.8 immediately. **Crossfade:** We don’t set alpha in ShowDiscoveryLine; updateEntrance (called from updateCrossfade) will animate discovery in if text is set. No bug; note in comments if desired.

### Missing / future system

- **Scenario start** (Delves, scenarios, party dungeon) is not yet a Presence type; see [feat-scenario-start-presence.plan.md](.cursor/plans/feat-scenario-start-presence.plan.md). Out of scope for this review but affects “systems shown” for 1.0 if you add it.

---

## Part 4: Visual UX Consistency

### Font and size

- **Presence:** Hardcoded `FONT_PATH = "Fonts\\FRIZQT__.TTF"`; title 48/36/20 by type, subtitle SUB_SIZE 24 (or cfg.sz when smaller), discovery DISCOVERY_SIZE 16. All "OUTLINE".
- **Focus:** Uses `addon.FONT_PATH` (Config: GetDefaultFontPath()), addon.HEADER_SIZE 16, TITLE_SIZE 13, OBJ_SIZE 11, SECTION size 10, with optional `fontOutline` option.
- **Inconsistency:** Presence does not use addon.FONT_PATH or addon font options; font is fixed. For 1.0 consistency, consider using **addon.FONT_PATH** (and optionally a single “Presence title outline” option) so global font changes apply to Presence.

### Shadow

- **Config:** addon.SHADOW_OX = 2, SHADOW_OY = -2, SHADOW_A = 0.8. Focus uses these for header/count shadows.
- **Presence:** Title shadow offset (2, -2) matches Config; **subtitle and discovery use (1, -1)**. Shadow alpha from addon.SHADOW_A at layer creation.
- **Recommendation:** Use SHADOW_OX/SHADOW_OY for all three (title, sub, discovery) so scaling is consistent; optionally reduce offset for smaller text (sub/discovery) via a scale factor rather than hardcoding (1,-1).

### Divider

- **Presence:** Divider 400x2, alpha 0.5 at rest, vertex color from title category. Focus uses addon.DIVIDER_HEIGHT 2 and addon.DIVIDER_COLOR (1,1,1,0.5). Presence divider is a separate element; colour is category-driven. Consistent conceptually; no change required unless you want divider alpha from Config.

### Colours

- Already covered: category/subCategory from GetQuestColor/QUEST_COLORS; boss and discovery from PRESENCE_*. Discovery should be resolved at show time. Rest is consistent with Focus colour matrix when Focus is loaded.

### Animation timing

- Presence: ENTRANCE_DUR 0.7, EXIT_DUR 0.8, CROSSFADE_DUR 0.4, ELEMENT_DUR 0.4, stagger delays 0 / 0.15 / 0.30 / 0.45. Focus: FADE_IN_DUR 0.4, FADE_OUT_DUR 0.4, etc. Presence is intentionally more cinematic (longer); no need to match Focus exactly. Document that Presence uses longer, cinematic timings.

### Summary: UX consistency to-dos

1. **Font:** Use addon.FONT_PATH in Presence (and optionally respect a font outline option) so typography aligns with the rest of the suite.
2. **Shadow offset:** Use addon.SHADOW_OX / SHADOW_OY for subtitle and discovery (or a derived value) instead of hardcoded (1, -1).
3. **Document** that Presence uses fixed, cinematic animation timings and larger type sizes by design.

---

## Implementation order (combined)

1. **Discovery colour at show time** — getDiscoveryColor() and set discovery text colour in PlayCinematic (when setting "Discovered") and in ShowDiscoveryLine().
2. **Optional colour refactor** — getCategoryColor(cat, default) and use for resolveColors and discovery; neutral defaults in CreateLayer for sub/discovery.
3. **UX consistency** — Switch Presence to addon.FONT_PATH; align shadow offsets with Config (SHADOW_OX/SHADOW_OY for sub and discovery, or scaled).
4. **Edge cases (optional for 1.0)** — Document combat/queue/zone order behaviour; consider queueing for post-combat or coalescing zone events if you want to refine later.
5. **Documentation** — Short comments: colour resolved at show time only; OnUpdate does not touch colour/text; Presence uses cinematic timings and larger fonts by design.

No new per-frame work; main robustness and 1.0 polish are discovery colour at show time, optional centralisation of colour resolution, and font/shadow consistency with the rest of Horizon Suite.