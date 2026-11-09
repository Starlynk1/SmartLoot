# SmartLoot notes

Working notes for this addon. The game does not load this file.

Source of truth for the WoW UI and API: https://github.com/Gethe/wow-ui-source

If a guide and that repo disagree, the repo wins. Record the branch and file path here when a call is locked in.

## Branches

- Retail (Midnight / standard): `live`. Check `ptr`, `ptr2`, and `beta` when a call may have moved on a test client.
- Forever: `forever`
- Later Classic Era: `classic_era` (`classic_era_ptr` for the test client)
- Later Anniversary: `classic_anniversary`
- Later MoP Classic: `classic` (`classic_ptr`, beta `classic_beta`)

`SmartLoot.toc` is the only TOC file. The interface line lists a client only when that version is ready to test. Right now that is `120100` Retail (12.1.0), `16001` Forever (1.60.1), and `11509` Classic Era (1.15.9). Add `50504` MoP Classic and `20506` Anniversary when those are finished.

Forever is not `WOW_PROJECT_MAINLINE`. Detect it with `GetBuildInfo`: interface `16000`–`19999`, or a version string starting with `1.60`. Retail remains `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Classic Era is `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC` (or toc `11500`–`11999`). Symlink: `_classic_era_\Interface\AddOns\SmartLoot` → this repo (same pattern as Retail / `_classic_beta_`).

Classic Era notes before first test: no Edit Mode (skip hooks); no transmog options; side options tabs like Forever; ranged compare slot 18; loot/options frames fall back if `DefaultPanelFlatTemplate` / `ButtonFrameTemplate` are missing; minimap uses the same centered round-plate layout as Forever/Retail.

## Behavior

SmartLoot turns `autoLootDefault` off while it is enabled and restores the previous value when it is disabled. The saved previous value lives in `SmartLootDB.savedAutoLoot` so a reload does not lose it.

The loot frame does not call `LootSlot`. The client autoloots before `LOOT_OPENED` when the cvar is on, or when the player holds the autoloot key. If that event arrives with autoloot already true, this open is left alone. Group loot rolls are handled only when auto-roll is on and the character is in a party or raid. `START_LOOT_ROLL` is the trigger. `GetLootRollItemLink` and `GetLootRollItemInfo` describe the roll. `RollOnLoot(rollID, 1)` needs and `RollOnLoot(rollID, 2)` greeds. A BoP confirm fires `CONFIRM_LOOT_ROLL`, and `ConfirmLootRoll` accepts only a roll this addon just made. Items under the minimum item level are left on the Blizzard roll window. A usable item with a higher item level than the weaker equipped piece in that slot is a Need. Everything else that can be greeded is a Greed. Missing transmog can be set to Need or Greed; an upgrade still needs. `C_TransmogCollection.GetItemInfo` plus `PlayerHasTransmogItemModifiedAppearance` decides whether the appearance is missing.

Loot order, highest tier first, then higher value:

1. Money and currency
2. Quest items
3. Account-bound gear
4. Bind-on-pickup gear
5. Bind-on-equip gear
6. Everything else by value

Gear means `itemEquipLoc` is set and is not `INVTYPE_NON_EQUIP_IGNORE`. A bind-on-equip recipe is not gear.

Value is Auctionator or TradeSkillMaster `dbmarket` when that option is on and the addon is loaded. Otherwise it is vendor `sellPrice` times count. Poor items always use vendor `sellPrice`, including when auction value is on. Vendor-purchased items (not crafted or looted) also use vendor `sellPrice` only: Trade Goods subclasses Parts, Other, and the classic Trade Goods catch-all, or any item with a known merchant buy price from Auctionator `GetVendorPriceByItemID` / TSM `vendorBuy`.

Empty slots only count when the bag family can hold the item. General bags (family 0) hold anything. A special bag holds an item only when the item family overlaps that bag, or the item is the matching trade good (leather in a skinning bag, herbs in an herb bag, ore in a mining bag). Deleting from a skinning bag frees a skinning slot only. If `GetContainerNumFreeSlots` reports family 0, the equipped bag item is checked with `GetItemFamily` and its container subclass. A reagent bag (container subclass 11) holds crafting reagents only. Leftover stack room is used before a new slot.

When more slots are required, every unlocked bag item is valued first, cheapest to dearest (Poor wins ties). The cheapest item that is not needed and not keepable gear is the destroy option. Needed means protected IDs, bag quest items, the Hearthstone, profession tools, summoned stones (healthstone, soulstone, firestone, spellstone), spell reagents by classification (Miscellaneous / Reagent or Reagent class — mage portal runes, ankhs, symbols, and similar), soul shards under the keep/capacity rules below, stacks still on the corpse, skipped openables, and crafting reagents when that option is on. Vendor trade supplies (same Parts / Other / classic Trade Goods subclasses) stay destroy-eligible; Forever empty vials are Other. Soul shards in a soul bag are never destroyed. Overflow shards in regular bags may be deleted only when the total is above soul-bag capacity (or when there is no soul bag) and above the Options “Soul shards to keep” floor (default 0). Keepable gear means usable equipped gear or a missing transmog. A delete is used only when the loot item's coin value is strictly higher than the combined value of the items deleted for it. That check applies to commons and to higher tiers, including gear. A quest item needed for an active quest is the exception, and so is the item that starts the next quest. Teronis' Journal is that case: the corpse turns in Raene's Cleansing and the journal begins the continuation, so the loot slot has a quest id with `isActive` false. Those items are always taken when a slot can be freed. A loot slot counts when `GetLootSlotInfo` reports `isQuestItem` or a quest id. If the corpse opens a quest offer instead of loot, or the game reports inventory full while that offer is up, the same destroy frame is used. `AcceptQuest`, `CompleteQuest`, or `GetQuestReward` runs after the slot is free when that offer is still open. A corpse that only reports inventory full, with no loot window, replaces the Looting rows with the message to click Destroy and Loot. Inventory full at a vendor (`MerchantFrame`) never starts a destroy. The purchase is left to the merchant window. The Deleting rows, coin values, and lock buttons stay. An openable item (`hasLoot`, an Open spell, or the “Right Click to Open” tooltip) is clickable in that frame. Clicking it tries to open the item first, so contents that fit in an existing stack do not require a delete. After that openable is opened and its contents are in the bags, the addon stops. Click the quest NPC or object again to take the quest item. If the game then reports inventory full, a new process frees a different slot and opens that item so the contents are kept. An openable shown for a quest item is opened or skipped. Skip is not a permanent protect. The item icon is the open click. The row shows the item tooltip. Cancel returns to the previous loot decision. Destroy and Loot deletes the cheapest bag item during that click, then retries the NPC with `C_PlayerInteractionManager.InteractUnit` on `target` or `npc`. A clickable object uses the `softinteract` unit. The target is left selected so that retry can run. A loot tooltip that contains `Quest Item` (`ITEM_BIND_QUEST`, read from `C_TooltipInfo.GetLootItem` or a hidden `SetLootItem` tooltip) counts, and so does an unfinished quest-objective line (`Enum.TooltipDataLineType.QuestObjective`). The quest log is checked with the tracker: `C_QuestLog.GetInfo` for every shown log entry, quest watches, and world-quest watches. A matching loot `questID`, or an unfinished `item` or `object` objective whose text names the item, counts. `GetLootSlotInfo`'s `isActive` flag is also accepted. The delete is the lowest value in the bags that frees a usable slot, including uncommon and better. For other loot the same cheapest-eligible rule applies. If nothing affordable fits, an openable bag item is still offered in Deleting, with its coin value and lock. That row can be clicked to open it. Otherwise the loot stays on the corpse and nothing is deleted. Quest loot may delete the cheapest eligible item of any quality. Locked items are never valued for destroy. Never destroy needed items or keepable gear for regular loot. Profession tools are item class Profession (19), equip location `INVTYPE_PROFESSION_TOOL` or `INVTYPE_PROFESSION_GEAR`, fishing poles (weapon subclass 20), and classic miscellaneous weapons (subclass 14: skinning knife, mining pick, blacksmith hammer, and the engineering tools). Never delete a stack of an item that is still on the corpse. Money, currency, and any item that fits in a current stack or empty slot are looted with `LootSlot` before a decision is offered. The decision frame shows one destroy-to-loot pair at a time: the junk being deleted and the single corpse item it frees space for (Looting N of M when several need space). After that delete and loot finish, the next pair is offered until the corpse is done. Left-behind items stay listed. Clicking a leftover row on the Blizzard loot window loots that item only; it does not delete junk. Options “Auto-close leftover loot” (slider, Off–15s, default 5s) closes the leftover window and Blizzard loot when nothing is being destroyed to take an item. A destroy-to-loot pair does not start that timer. Options “Auto-destroy when looting” skips the confirm window only when a single item needs space and the junk is at or below the chosen quality (Grey, White, or Green; default Grey). Two or more items that need space always use Destroy and Loot one pair at a time. `DeleteCursorItem` is protected, so the addon does not delete from the loot scan. Bags are scanned on bag updates into a live list; items at or below that quality cap (excluding keeps) are kept sorted by vendor value. `FindJunk` only arms a bag/slot; WorldFrame mouse and an invisible pass-through click frame (`EnableMouse(false)`, `SetMouseClickEnabled(true)`, BACKGROUND) handle a single auto-destroy. Keyboard `SetPropagateKeyboardInput` is skipped (protected). Coin value still has to be a gain at every quality. Openables and quest/open-grant prompts still use the decision frame. The delete row has a lock button: unlocked when the item can be deleted, locked when it is protected. Clicking the unlocked lock protects that item and builds a new recommendation. Every row shows that item's coin value with gold, silver, and copper icons. Cancel and Escape call `CloseLoot`, which also closes the Blizzard loot window. If every loot slot is empty, `CloseLoot` runs so the empty Blizzard window does not stay up. `DeleteCursorItem` is protected: the button picks the bag item up on mouse down and deletes it on mouse up. Only one destroy runs per click; if another delete is still needed, click Destroy and Loot again. `DELETE_GOOD_ITEM` is never accepted by the addon. When a quest item needs that delete, the prompt stays up so it can be typed in.

## Verified API

Checked on `live` unless noted. The same `LootFrame.lua` path exists on `forever`.

- Loot window: `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua`
  - `GetNumLootItems`, `GetLootSlotInfo`, `GetLootSlotType`, `GetLootSlotLink`, `LootSlot`
  - `LOOT_OPENED` only fills the list. It does not loot.
- Loot events: `Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua`
  - `LOOT_OPENED` payload is `autoLoot`, `isFromItem`
  - `LOOT_BIND_CONFIRM` payload is `lootSlot`
  - `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`
- Addon compartment: `Interface/AddOns/Blizzard_Minimap/Mainline/AddonCompartment.lua` on `forever` and `live`. `AddonCompartmentFrame:RegisterAddon` adds an entry. There is no unregister, so the entry is removed from `registeredAddons` and `UpdateDisplay` is called. Checked on `forever`.
- Minimap button: 31x31 with `MiniMap-TrackingBorder`. All clients use a centered ~23px icon and border 50 (same as Forever/Retail). LibDBIcon’s classic TOPLEFT inset is for square icons and does not center this round plate. Radius is `floor(mapRadius + buttonRadius - 9)` so the button sits around the ring, not on it. Art: bold bag + lightbulb. `Art/SmartLoot-Icon` (TGA) is `## IconTexture` and the compartment icon — transparent background. `Art/SmartLoot-Portrait` (opaque charcoal) is the options frame portrait via `SetPortraitTextureRaw` and the Forever Loot side-tab icon. In-game size is reduced with portrait tex coords / tab icon size only — art files are not rescaled. Round `Art/SmartLoot-Minimap` (TGA) is the minimap button. `Art/SmartLoot.png` is the CurseForge / Git logo with charcoal fill, gold rounded border, and transparent corners (under 1 MB). TGAs are 128x128 32-bit BGRA bottom-up.
- Bags: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua`
  - `C_Container.GetContainerItemInfo` returns `ContainerItemInfo`
  - `C_Container.GetContainerNumFreeSlots` returns free count and bag family
  - `C_Container.PickupContainerItem`
  - `BAG_UPDATE_DELAYED`
  - Bag clicks: `ContainerFrameItemButtonMixin:OnModifiedClick` in `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`
- Items: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
  - `C_Item.GetItemInfo` returns bind type, sell price, equip loc, and `isCraftingReagent`
  - `C_Item.GetItemFamily`, `C_Item.IsItemBindToAccount`, `C_Item.IsItemBindToAccountUntilEquip`
- Dialogs: `Interface/AddOns/Blizzard_StaticPopup_Game/GameDialogDefs.lua`
  - `LOOT_BIND` accept calls `ConfirmLootSlot`
  - `DELETE_ITEM` accept calls `DeleteCursorItem`
  - `DELETE_GOOD_ITEM` is the typed DELETE dialog in `Mainline/GameDialogDefs.lua`
- Edit Mode: `Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua` and `Shared/EditModeSystemTemplates.xml`
  - Only the loot decision frame is in Edit Mode. The options frame is a normal window: drag it while it is open, and `SmartLootDB.optionsPosition` is restored the next time it opens
  - `EnterEditMode` fires `EditMode.Enter`. `ExitEditMode` fires `EditMode.Exit`
  - Do not call `RegisterSystemFrame` (it taints Edit Mode). Snap uses `EditModeSystemMixin` methods and `EditModeMagnetismManager:ApplyMagnetism`, and does not `RegisterFrame`
  - The selection overlay is a child of the loot frame, raised above its other pieces. `Art/EditModeHighlighted.blp` while idle, `Art/EditModeSelected.blp` after the click, and "Click to Edit" on hover. Snap sides come from the loot frame rect, not the border texture
  - The settings dialog uses `DialogBorderTranslucentTemplate` and sits beside `EditModeManagerFrame` until it is dragged
  - `C_EditMode.GetLayouts().activeLayout` is the layout index
  - Position, scale, and font size are written to `layouts[activeLayout].decision` as soon as they change, and again when Edit Mode closes. Reopening Edit Mode loads that layout. `PLAYER_LOGIN` and `EDIT_MODE_LAYOUTS_UPDATED` apply it again once the active layout index is known
- Windows: the options frame uses `ButtonFrameTemplate` in `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`. The loot decision frame uses `DefaultPanelFlatTemplate` from that same file. That is the loot window chrome (`ScrollingFlatPanelTemplate` inherits it, layout `ButtonFrameTemplateNoPortrait`), so there is no round portrait icon. The scrolling loot template is not used, because its close animation moves the frame.
  - Options still uses `frame.Inset`, `SetTitle`, and `SetPortraitToAsset`. The loot frame uses `SetTitle` only
  - Options tabs: Forever uses right-side spellbook skill tabs (`Interface\SpellBook\SpellBook-SkillLineTab`, stacked from `TOPRIGHT`). Retail uses bottom `PanelTabButtonTemplate` buttons named `SmartLootOptionsFrameTab1` through `Tab3` (Loot, Rolls, Protected), selected with `PanelTemplates_SetNumTabs` and `PanelTemplates_SetTab`
- Buttons: `UICheckButtonTemplate` (`Text` key) and `UIPanelButtonTemplate`
- Edit Mode sliders: `MinimalSliderWithSteppersTemplate` in `Interface/AddOns/Blizzard_SharedXML/Shared/Slider/MinimalSlider.lua`
  - `OptionsSliderTemplate` is classic-only, so it is not used here
- Input: `InputBoxTemplate` in `Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml`
