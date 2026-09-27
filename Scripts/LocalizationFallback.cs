using System;
using System.Collections.Generic;
using HarmonyLib;
using UnityEngine;

namespace VietnameseCoreKeeper
{
    /// <summary>
    /// Guarantees the localization fallback chain for every term I2 knows about.
    ///
    /// Provenance is explicit, never inferred from the text. VietnameseKeys.g.cs is
    /// generated from Localization/Localization.csv and lists exactly the keys
    /// VietnameseCoreKeeper supplies, so membership in that set is the only thing
    /// that decides whether a term is ours. Nothing here inspects characters, so a
    /// Vietnamese value that is pure ASCII, a name, an acronym or a number is
    /// protected exactly like a fully accented one, and an English value is never
    /// mistaken for a translation.
    ///
    ///   key supplied by VietnameseCoreKeeper        -> c0 kept exactly as-is
    ///   key not supplied by us, English known       -> c0 = that English
    ///   key not supplied by us, no English anywhere -> c0 = the raw localization key
    ///
    /// The last two tiers always write something, so no term can be left unresolved.
    ///
    /// Why this is needed: Core Keeper imports the base Localization.csv and then every
    /// mod's Localization/Localization.csv into I2 from a single call site,
    /// PugMod.ModManager.Init (ImportAndUpdateCustomCsv then
    /// ImportAndUpdateExtraCustomCsv). Both write into the same I2 language source, so
    /// at runtime there is no way to tell which mod contributed a term. TextManager.Init2
    /// runs after that, so this one-shot postfix sees localization from mods
    /// VietnameseCoreKeeper has never heard of, with no republish.
    ///
    /// Constraints honoured: no System.Reflection, no MemberInfo, no file IO, no path
    /// discovery, no new framework, no Update()/polling, no per-frame work. The key set
    /// and the English map are each built once per init.
    /// </summary>
    [HarmonyPatch(typeof(TextManager), "Init2")]
    internal static class LocalizationFallback
    {
        private const string VietnameseCode = "c0";
        private static readonly string[] EnglishCodes = { "English", "en", "English (US)" };
        private static bool _ran;

        [HarmonyPostfix]
        private static void Postfix()
        {
            try
            {
                if (_ran) { return; }
                _ran = true;

                List<I2.Loc.LanguageSourceData> sources = I2.Loc.LocalizationManager.Sources;
                if (sources == null || sources.Count == 0)
                {
                    Debug.Log("[VietnameseFallback] no I2 sources; nothing to do.");
                    return;
                }

                // Authoritative provenance: exactly the keys VietnameseCoreKeeper ships.
                HashSet<string> ours = new HashSet<string>(VietnameseKeys.All, StringComparer.Ordinal);
                Debug.Log("[VietnameseFallback] VietnameseCoreKeeper keys: " + ours.Count);

                // English provenance, built once from sources that expose a real English
                // column. A source whose only language is c0 contributes nothing, so c0
                // is never used as its own English reference.
                Dictionary<string, string> english = BuildEnglishMap(sources);

                int kept = 0, resolvedEnglish = 0, resolvedKey = 0, noVietnameseSlot = 0, oursSeen = 0;

                for (int s = 0; s < sources.Count; s++)
                {
                    I2.Loc.LanguageSourceData source = sources[s];
                    if (source == null) { continue; }

                    List<string> codes = source.GetLanguagesCode(true, false);
                    if (codes == null || codes.Count == 0) { continue; }

                    int vietnamese = IndexOfCode(codes, VietnameseCode);
                    if (vietnamese < 0)
                    {
                        // No Vietnamese column here (the source that carries the game's
                        // other languages). Nothing can be written and inventing a slot
                        // would change the engine's language table.
                        noVietnameseSlot++;
                        continue;
                    }

                    List<string> terms = source.GetTermsList(null);
                    if (terms == null) { continue; }

                    int sKept = 0, sEnglish = 0, sKey = 0;
                    for (int t = 0; t < terms.Count; t++)
                    {
                        string term = terms[t];

                        if (ours.Contains(term))
                        {
                            // Supplied by VietnameseCoreKeeper. Authoritative; never touch it.
                            sKept++;
                            oursSeen++;
                            continue;
                        }

                        I2.Loc.TermData data = source.GetTermData(term, false);
                        if (data == null || data.Languages == null) { continue; }
                        if (vietnamese >= data.Languages.Length) { continue; }

                        string original;
                        english.TryGetValue(term, out original);
                        if (IsMissing(original)) { original = null; }

                        if (original != null)
                        {
                            data.Languages[vietnamese] = original;
                            sEnglish++;
                        }
                        else
                        {
                            // No Vietnamese from us and no English anywhere: expose the raw
                            // key so the term is identifiable rather than blank.
                            data.Languages[vietnamese] = term;
                            sKey++;
                        }
                    }

                    kept += sKept;
                    resolvedEnglish += sEnglish;
                    resolvedKey += sKey;
                    Debug.Log("[VietnameseFallback] source " + s + " terms=" + terms.Count +
                              " kept=" + sKept + " english=" + sEnglish + " key=" + sKey);
                }

                if (oursSeen != ours.Count)
                {
                    Debug.LogWarning("[VietnameseFallback] " + (ours.Count - oursSeen) +
                                     " VietnameseCoreKeeper key(s) are absent from the loaded sources.");
                }

                Debug.Log("[VietnameseFallback] applied: " + kept + " Vietnamese kept untouched, " +
                          resolvedEnglish + " resolved to original English, " +
                          resolvedKey + " resolved to the raw key, " +
                          "0 unresolved, " + noVietnameseSlot + " source(s) had no Vietnamese slot.");
            }
            catch (Exception exception)
            {
                Debug.LogError("[VietnameseFallback] failed: " + exception.Message);
            }
        }

        /// <summary>
        /// Collects the English text each source publishes, keyed by term. Only sources
        /// that expose a genuinely named English column are read, so a c0-only source is
        /// never used as its own English reference.
        /// </summary>
        private static Dictionary<string, string> BuildEnglishMap(List<I2.Loc.LanguageSourceData> sources)
        {
            Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.Ordinal);

            for (int s = 0; s < sources.Count; s++)
            {
                I2.Loc.LanguageSourceData source = sources[s];
                if (source == null) { continue; }

                List<string> codes = source.GetLanguagesCode(true, false);
                if (codes == null || codes.Count == 0) { continue; }

                int english = IndexOfEnglish(codes);
                if (english < 0) { continue; }

                List<string> terms = source.GetTermsList(null);
                if (terms == null) { continue; }

                for (int t = 0; t < terms.Count; t++)
                {
                    string term = terms[t];
                    I2.Loc.TermData data = source.GetTermData(term, false);
                    if (data == null || data.Languages == null) { continue; }
                    if (english >= data.Languages.Length) { continue; }

                    string value = data.Languages[english];
                    if (IsMissing(value)) { continue; }
                    if (!map.ContainsKey(term)) { map[term] = value; }
                }
            }

            Debug.Log("[VietnameseFallback] English provenance entries: " + map.Count);
            return map;
        }

        /// <summary>True when a cell carries no usable text at all.</summary>
        private static bool IsMissing(string value)
        {
            return string.IsNullOrEmpty(value) || value == "---";
        }

        private static int IndexOfCode(List<string> codes, string wanted)
        {
            for (int i = 0; i < codes.Count; i++)
                if (codes[i] != null && codes[i].Trim().Equals(wanted, StringComparison.OrdinalIgnoreCase))
                    return i;
            return -1;
        }

        /// <summary>
        /// Finds a real English column. Deliberately does NOT fall back to index 0: for the
        /// merged source index 0 is c0 itself, and using it would make every Vietnamese
        /// value look like its own English reference.
        /// </summary>
        private static int IndexOfEnglish(List<string> codes)
        {
            for (int e = 0; e < EnglishCodes.Length; e++)
            {
                int i = IndexOfCode(codes, EnglishCodes[e]);
                if (i >= 0) { return i; }
            }
            return -1;
        }
    }
}
